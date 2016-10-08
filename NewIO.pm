use nqp;

my constant Path = IO::Path;

my role Encoding {}
my role Encoding::Decoder {}

my role IO { ... }

my role IO::Stream {
    sub unsupported(&method) is hidden-from-backtrace {
        die "IO operation '{&method.name}' not supported by {::?CLASS.^name}";
    }

    method close(--> True) { unsupported &?ROUTINE }

    method read(Int:D --> blob8:D) { unsupported &?ROUTINE }
    method readline(--> blob8:D) { unsupported &?ROUTINE }
    method readall(--> blob8:D) { unsupported &?ROUTINE }
    method write(blob8:D --> True) { unsupported &?ROUTINE }
    method getbyte(--> uint8) { unsupported &?ROUTINE }
    method putbyte(uint8 --> True) { unsupported &?ROUTINE }

    method uniread(Int:D --> Uni:D) { unsupported &?ROUTINE }
    method unireadall(--> Uni:D) { unsupported &?ROUTINE }
    method uniwrite(Uni:D --> True) { unsupported &?ROUTINE }
    method uniget(--> Uni:D) { unsupported &?ROUTINE }
    method unigetc(--> uint32) { unsupported &?ROUTINE }
    method uniput(--> Uni:D) { unsupported &?ROUTINE }
    method uniputc(uint32 --> True) { unsupported &?ROUTINE }

    method readchars(Int:D --> Str:D) { unsupported &?ROUTINE }
    method readallchars(--> Str:D) { unsupported &?ROUTINE }
    method print(Str:D --> True) { unsupported &?ROUTINE }
    method print-nl(--> True) { unsupported &?ROUTINE }
    method get(--> Str:D) { unsupported &?ROUTINE }
    method getc(--> Str:D) { unsupported &?ROUTINE }
    method put(Str:D --> True) { unsupported &?ROUTINE }
}

my role IO::CodedStream does IO::Stream {
    method encoding(--> Encoding:D) { ... }
    method decoder(--> Encoding::Decoder:D) { ... }
    method source(--> IO::Stream:D) { ... }

    method close {
        self.source.close;
        self.decoder.reset;
    }

    method readall(--> blob8:D) {
        my \decoder = self.decoder;
        decoder.add-bytes(self.source.readall);
        decoder.consume-all-bytes;
    }

    method unireadall(--> Uni:D) {
        my \decoder = self.decoder;
        decoder.add-bytes(self.source.readall);
        decoder.consume-all-codes;
    }

    method readallchars(--> Str:D) {
        my \decoder = self.decoder;
        decoder.add-bytes(self.source.readall);
        decoder.consume-all-chars;
    }
}

my class IO::VMHandle does IO::Stream {
    has $!fh;

    sub mode(
        :$r, :$w, :$x, :$a, :$update,
        :$rw, :$rx, :$ra,
        :$mode is copy,
        :$create is copy,
        :$append is copy,
        :$truncate is copy,
        :$exclusive is copy,
        *%
    ) {
        $mode //= do {
            when so ($r && $w) || $rw { $create              = True; 'rw' }
            when so ($r && $x) || $rx { $create = $exclusive = True; 'rw' }
            when so ($r && $a) || $ra { $create = $append    = True; 'rw' }

            when so $r { 'ro' }
            when so $w { $create = $truncate  = True; 'wo' }
            when so $x { $create = $exclusive = True; 'wo' }
            when so $a { $create = $append    = True; 'wo' }

            when so $update { 'rw' }

            default { 'ro' }
        }

        $mode = do given $mode {
            when 'ro' { 'r' }
            when 'wo' { '-' }
            when 'rw' { '+' }
            default { die "Unknown mode '$_'" }
        }

        $mode = join '', $mode,
            $create    ?? 'c' !! '',
            $append    ?? 'a' !! '',
            $truncate  ?? 't' !! '',
            $exclusive ?? 'x' !! '';

        $mode;
    }

    method new(Mu \fh --> IO::VMHandle:D) {
        nqp::create(self)!SET-FH(nqp::decont(fh));
    }

    method perl(--> Str:D) {
        'IO::VMHandle.new(...)';
    }

    method !SET-FH(Mu \fh) {
        $!fh := fh;
        self;
    }

    method open-file(Str:D \path --> IO::VMHandle:D) {
        self.new(nqp::open(path, mode(|%_)));
    }

    method stdin(--> IO::VMHandle:D) { self.new(nqp::getstdin()) }
    method stdout(--> IO::VMHandle:D) { self.new(nqp::getstdout()) }
    method stderr(--> IO::VMHandle:D) { self.new(nqp::getstderr()) }

    method fd(--> int) {
        nqp::filenofh($!fh);
    }

    method close(--> True) {
        nqp::closefh($!fh);
    }

    method read(Int:D \n --> blob8:D) {
        nqp::readfh($!fh, buf8.new, nqp::unbox_i(n)) || Nil;
    }

    method readall(--> blob8:D) {
        my \buf = buf8.new;
        loop { buf.append(nqp::readfh($!fh, buf8.new, 0x100000) || last) }
        buf;
    }

    method write(blob8:D \buf --> True) {
        nqp::writefh($!fh, buf);
    }
}

my class IO::Handle does IO::CodedStream {
    has $.source;
    has $.encoding;
    has $.decoder;

    submethod BUILD(:$!source, :$enc) {
        given $enc {
            when Encoding {
                $!encoding = $enc;
                $!decoder = $!encoding.decoder;
            }
        }
    }
}

my role IO {
    method open-stream(--> IO::Stream:D) { ... }

    method handle-type(--> IO::Handle:U) { IO::Handle }

    method open(--> IO::Handle:D) {
        self.handle-type.new(source => self.open-stream(|%_), io => self, |%_);
    }

    proto method slurp {*}
    multi method slurp(:$bin! --> blob8:D) {
        my \stream = self.open(|%_);
        LEAVE stream.close;
        stream.readall;
    }
    multi method slurp(:$uni! --> Uni:D) {
        my \stream = self.open(|%_);
        LEAVE stream.close;
        stream.unireadall;
    }
    multi method slurp(--> Str:D) {
        my \stream = self.open(|%_);
        LEAVE stream.close;
        stream.readallchars;
    }

    proto method lines {*}
    multi method lines(:$bin! --> Seq:D) {
        my \stream = self.open(|%_);
        Seq.new(nqp::create(class :: does Iterator {
            method pull-one() is raw {
                stream.readline // do {
                    stream.close;
                    IterationEnd
                }
            }

            method push-all(\target --> IterationEnd) {
                my $line;
                target.push($line) while ($line := stream.readline).DEFINITE;
                stream.close;
            }
        }));
    }
    multi method lines(:$uni! --> Seq:D) {
        my \stream = self.open(|%_);
        Seq.new(nqp::create(class :: does Iterator {
            method pull-one() is raw {
                stream.uniget // do {
                    stream.close;
                    IterationEnd
                }
            }

            method push-all(\target --> IterationEnd) {
                my $line;
                target.push($line) while ($line := stream.uniget).DEFINITE;
                stream.close;
            }
        }));
    }
    multi method lines(--> Seq:D) {
        my \stream = self.open(|%_);
        Seq.new(nqp::create(class :: does Iterator {
            method pull-one() is raw {
                stream.get // do {
                    stream.close;
                    IterationEnd
                }
            }

            method push-all(\target --> IterationEnd) {
                my $line;
                target.push($line) while ($line := stream.get).DEFINITE;
                stream.close;
            }
        }));
    }
}

my class IO::FileHandle is IO::Handle {
    has $.path;
    submethod BUILD(:$io) { $!path = Path.new-from-absolute-path($io.abspath) }
}

my role IO::FileIO does IO {
    method abspath(--> Str:D) { ... }

    method handle-type(--> IO::Handle:U) { IO::FileHandle }

    method open-stream(--> IO::Stream:D) {
        IO::VMHandle.open-file(self.abspath, |%_);
    }
}

my class IO::Path is Path does IO::FileIO {}

sub EXPORT {
    BEGIN Map.new((
        IO => IO,
        Encoding => Encoding,
    ));
}
