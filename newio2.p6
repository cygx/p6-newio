use NativeCall;
use MONKEY-TYPING;
use nqp;

sub newio_errormsg(int64 --> Str) is native<newio.dll> {*}
sub newio_stdhandle(uint32 --> uint64) is native<newio.dll> {*}
sub newio_close(uint64 --> int64) is native<newio.dll> {*}
sub newio_size(uint64 --> int64) is native<newio.dll> {*}
sub newio_getpos(uint64 --> int64) is native<newio.dll> {*}
sub newio_open(Str is encoded<utf16>, uint64 --> uint64) is native<newio.dll> {*}
sub newio_validate(uint64 --> int64) is native<newio.dll> {*}
sub newio_read(uint64, buf8, uint64, uint64 --> int64) is native<newio.dll> {*}
sub newio_copy(buf8, blob8, uint64, uint64, uint64) is native<newio.dll> {*}
sub newio_move(buf8, blob8, uint64, uint64, uint64) is native<newio.dll> {*}
sub newio_decode_latin1(Uni, blob8, int64 --> int64) is native<newio.dll> {*}

my constant Path = IO::Path;
my constant NUL = "\0";
my constant BLOCKSIZE = 512;

my role Encoding {
    method min-bytes-per-code { ... }
    method max-bytes-per-code { ... }
    method decode(blob8:D --> Uni:D) { ... }
#    method encode(Uni:D --> blob8:D) { ... }
}

my class Encoding::Latin1 does Encoding {
    method min-bytes-per-code { 1 }
    method max-bytes-per-code { 1 }

    method decode(blob8:D $bytes --> Uni:D) {
        my int $count = $bytes.elems;
        my $uni := nqp::create(Uni);
        nqp::setelems($uni, $count);
        newio_decode_latin1($uni, $bytes, $count);
        $uni;
    }
}

my class Encoding::Utf8 does Encoding {
    method min-bytes-per-code { 1 }
    method max-bytes-per-code { 4 }
    method decode(blob8:D --> Uni:D) { !!! }
}

my %ENCODINGS =
    'latin1' => Encoding::Latin1,
    'utf8' => Encoding::Utf8;

my role IO { ... }

my role IO::Handle {
    method close(--> True) {
        self.CLOSE;
    }

    method size(--> UInt:D) {
        self.GET-SIZE;
    }

    proto method seek($) {*}

    multi method seek(UInt:D $pos --> True) {
        self.DROP-BYTES;
        self.SET-POS($pos);
    }

    multi method seek(WhateverCode $pos --> True) {
        self.DROP-BYTES;
        self.SET-POS-FROM-END($pos(0));
    }

    method skip(Int:D $offset --> True) {
        self.SET-POS-FROM-CURRENT($offset - self.DROP-BYTES);
    }

    method tell(--> UInt:D) {
        self.GET-POS - self.AVAILABLE-BYTES;
    }

    method read(UInt:D $n --> blob8:D) {
        my $buf := buf8.allocate(self.LOAD-BYTES($n));
        self.CONSUME-BYTES($buf);
    }

    method readline(--> blob8:D) {
        my $buf := buf8.allocate(self.LOAD-LINE);
        self.CONSUME-BYTES($buf);
    }

    method readall(--> blob8:D) {
        self.READALL;
    }

    method write(blob8:D $bytes --> True) { die }
    method getbyte(--> uint8) { die }
    method putbyte(uint8 $byte --> True) { die }

    method uniread(UInt:D $n --> Uni:D) { die }

    method unireadall(--> Uni:D) {
        self.ENCODING.decode(self.READALL);
    }

    method uniwrite(Uni:D $uni --> True) { die }
    method uniget(--> Uni:D) { die }
    method unigetc(--> uint32) { die }
    method uniput(Uni:D $uni --> True) { die }
    method uniputc(uint32 $cp --> True) { die }

    method readchars(UInt:D $n --> Str:D) { die }

    method readallchars(--> Str:D) {
        nqp::strfromcodes(self.unireadall);
    }

    method print(Str:D $str --> True) { die }
    method print-nl(--> True) { die  }
    method get(--> Str:D) { die }
    method getc(--> Str:D) { die }
    method put(Str:D $str --> True) { die }
}

my role IO[IO::Handle:U \HANDLE] {
    method open(--> IO::Handle:D) {
        HANDLE.new(io => self, |%_);
    }

    proto method slurp {*}
    multi method slurp(:$bin! --> blob8:D) {
        my \handle = self.open(|%_);
        LEAVE handle.close;
        handle.readall;
    }
    multi method slurp(:$uni! --> Uni:D) {
        my \handle = self.open(|%_);
        LEAVE handle.close;
        handle.unireadall;
    }
    multi method slurp(--> Str:D) {
        my \handle = self.open(|%_);
        LEAVE handle.close;
        handle.readallchars;
    }
}

my class IO::OsHandle does IO::Handle {
    has uint64 $.fd;

    method SET($!fd) is hidden-from-backtrace {
        my $rv := newio_validate($!fd);
        die X::IO.new(os-error => newio_errormsg($rv))
            if $rv < 0;
    }

    method GET-SIZE is hidden-from-backtrace {
        my $size := newio_size($!fd);
        die X::IO.new(os-error => newio_errormsg($size))
            if $size < 0;

        $size;
    }

    method GET-POS is hidden-from-backtrace {
        my $pos := newio_getpos($!fd);
        die X::IO.new(os-error => newio_errormsg($pos))
            if $pos < 0;

        $pos;
    }

    method CLOSE is hidden-from-backtrace {
        my $rv = newio_close($!fd);
        die X::IO.new(os-error => newio_errormsg($rv))
            if $rv < 0;
    }

    method AVAILABLE-BYTES {
        0;
    }
}

my class IO::BufferedOsHandle is IO::OsHandle {
    has $!bytes = buf8.allocate(BLOCKSIZE);
    has uint $!pos;
    has $.encoding;

    sub round-up(uint $u, uint $m = BLOCKSIZE) {
        (($u + $m - 1) div $m) * $m;
    }

    submethod BUILD(:$enc = Encoding::Utf8) {
        $!encoding = do given $enc {
            when Encoding { $enc }
            when %ENCODINGS{$enc}:exists { %ENCODINGS{$enc} }
            default { die "unsupported encoding '$enc'" }
        }
    }

    method ENCODING { $!encoding }

    method AVAILABLE-BYTES {
        $!pos;
    }

    method READALL {
        my uint $have = self.AVAILABLE-BYTES;
        my uint $rest = self.GET-SIZE - self.GET-POS;
        my uint $all = $have + $rest;
        my $buf := buf8.allocate($all);
        newio_copy($buf, $!bytes, 0, 0, $have);
        my int64 $rv = newio_read($.fd, $buf, $have, $rest);
        die X::IO.new(os-error => newio_errormsg($rv)) if $rv < 0;
        die X::IO.new(os-error => 'underflow') if $rv != $rest;
        $buf;
    }

    method LOAD-BYTES(uint $n) {
        if $n <= $!pos { $n }
        else {
            my uint $size = $!bytes.elems;
            my uint $want = round-up $n;
            $!bytes.reallocate($want)
                if $want < $size;

            my int64 $rv = newio_read($.fd, $!bytes, $!pos, $want - $!pos);
            die X::IO.new(os-error => newio_errormsg($rv))
                if $rv < 0;

            $!pos += $rv;
        }
    }

    method CONSUME-BYTES($buf) {
        die 'underflow' if $buf.elems < $!pos;
        my uint $len = $buf.elems;
        my uint $rem = $!pos - $len;
        newio_copy($buf, $!bytes, 0, 0, $len);
        newio_move($!bytes, $!bytes, 0, $len, $rem) if $rem > 0;
        $buf;
    }
}

my class IO::FileHandle is IO::BufferedOsHandle {
    has $.path;
    has uint64 $.mode;

    sub mode(
        :$r, :$u, :$w, :$a, :$x, :$ru, :$rw, :$ra, :$rx,
        :$read is copy, :$write is copy, :$append is copy,
        :$create is copy, :$exclusive is copy, :$truncate is copy,
        *%
    ) {
        $read = True if $r;
        $write = True if $u;
        $write = $create = $truncate = True if $w;
        $write = $create = $append = True if $a;
        $write = $create = $exclusive = True if $x;
        $read = $write = True if $ru;
        $read = $write = $create = $truncate = True if $rw;
        $read = $write = $create = $append = True if $ra;
        $read = $write = $create = $exclusive = True if $rx;
        ?$read +| ?$write +< 1 +| ?$append +< 2
            +| ?$create +< 3 +| ?$exclusive +< 4 +| ?$truncate +< 5;
    }

    submethod BUILD(:$io) {
        $!path = $io.absolute;
        $!mode = mode |%_;
        self.SET: newio_open($!path ~ NUL, $!mode);
    }
}

my class IO::StdHandle is IO::BufferedOsHandle {
    has uint32 $.id;

    proto sub id(*%) {*}
    multi sub id(:$in!, *%)  { 0 }
    multi sub id(:$out!, *%) { 1 }
    multi sub id(:$err!, *%) { 2 }
    multi sub id(:$w!, *%)   { 1 }
    multi sub id(:$r?, *%)   { 0 }

    submethod BUILD {
        self.SET: newio_stdhandle($!id = id |%_);
    }
}

my class IO::Std does IO[IO::StdHandle] {}

my class IO::Path is Path does IO[IO::FileHandle] {
    method gist { "{self.Str.perl}.IO" }
    method perl { "IO::Path.new({self.Str.perl})" }
}

augment class Str {
    method IO { IO::Path.new(self) }
}

sub open(IO() $_ = IO::Std, *%_) { .open(|%_) }

say open(:err);
say 'foo.txt'.IO.slurp(:enc<latin1>).perl;

my \N = 1000;
my \FILE = 'test.p6';

do {
    my $path = Path.new(FILE);
    my $i = 0;
    my $start = now;
    $i += $path.slurp(:enc<latin1>).chars for ^N;
    my $end = now;
    say $end - $start;
    say $i;
}

do {
    my $path = IO::Path.new(FILE);
    my $i = 0;
    my $start = now;
    $i += $path.slurp(:enc<latin1>).chars for ^N;
    my $end = now;
    say $end - $start;
    say $i;
}
