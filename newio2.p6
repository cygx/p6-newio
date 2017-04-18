use NativeCall;
use MONKEY-TYPING;

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

my constant Path = IO::Path;
my constant NUL = "\0";
my constant BLOCKSIZE = 512;

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
        my $want := self.GET-SIZE - self.GET-POS + self.AVAILABLE-BYTES;
        my $buf := buf8.allocate($want);
        self.LOAD-BYTES($want);
        self.CONSUME-BYTES($buf);
    }

    method write(blob8:D $bytes --> True) { die }
    method getbyte(--> uint8) { die }
    method putbyte(uint8 $byte --> True) { die }

    method uniread(UInt:D $n --> Uni:D) { die }
    method unireadall(--> Uni:D) { die }
    method uniwrite(Uni:D $uni --> True) { die }
    method uniget(--> Uni:D) { die }
    method unigetc(--> uint32) { die }
    method uniput(Uni:D $uni --> True) { die }
    method uniputc(uint32 $cp --> True) { die }

    method readchars(UInt:D $n --> Str:D) { die }
    method readallchars(--> Str:D) { die }
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

    sub round-up(uint $u, uint $m = BLOCKSIZE) {
        (($u + $m - 1) div $m) * $m;
    }

    method AVAILABLE-BYTES {
        $!pos;
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
        :$create is copy, :$exclusive is copy, :$truncate is copy
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
    multi sub id(:$in!)  { 0 }
    multi sub id(:$out!) { 1 }
    multi sub id(:$err!) { 2 }
    multi sub id(:$w!)   { 1 }
    multi sub id(:$r?)   { 0 }

    submethod BUILD(:$io) {
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
my $fh := 'foo.txt'.IO.open(:r);
say $fh;
say $fh.readall.decode.perl;
