use NativeCall;
use MONKEY-TYPING;

sub newio_errormsg(int64 --> Str) is native<newio.dll> {*}
sub newio_stdhandle(uint32 --> uint64) is native<newio.dll> {*}
sub newio_close(uint64 --> int64) is native<newio.dll> {*}
sub newio_size(uint64 --> int64) is native<newio.dll> {*}

my constant Path = IO::Path;

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
        my $buf := buf8.allocate(
            self.GET-SIZE - self.GET-POS + self.AVAILABLE-BYTES);

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

    method SET($!fd) {}

    method GET-SIZE is hidden-from-backtrace {
        my $size := newio_size($!fd);
        die X::IO.new(os-error => newio_errormsg($size))
            if $size < 0;

        $size;
    }

    method CLOSE is hidden-from-backtrace {
        my $rv = newio_close($!fd);
        die X::IO.new(os-error => newio_errormsg($rv))
            if $rv < 0;
    }
}

my class IO::FileHandle is IO::OsHandle {
    has $.path;
    submethod BUILD(:io($!path)) {}
}

my class IO::StdHandle is IO::OsHandle {
    has $.id;

    submethod BUILD {
        self.OPEN(|%_);
    }

    proto method OPEN {*}
    multi method OPEN(:$in!)  { self.SET: newio_stdhandle($!id = 0) }
    multi method OPEN(:$out!) { self.SET: newio_stdhandle($!id = 1) }
    multi method OPEN(:$err!) { self.SET: newio_stdhandle($!id = 2) }
    multi method OPEN(:$w!)   { self.SET: newio_stdhandle($!id = 1) }
    multi method OPEN(:$r?)   { self.SET: newio_stdhandle($!id = 0) }
}

my class IO::Std does IO[IO::StdHandle] {}

my class IO::Path is Path does IO[IO::FileHandle] {
    method gist { "{self.Str.perl}.IO" }
    method perl { "IO::Path.new({self.Str.perl})" }
}

augment class Str {
    proto method IO {*}
    multi method IO('-':) { IO::Std }
    multi method IO { IO::Path.new(self) }
}

sub open(IO() $_, *%_) { .open(|%_) }

say '-'.IO.open(:err);
say 'foo.txt'.IO.open
