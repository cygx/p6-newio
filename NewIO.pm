# TODO: reposition cursor before writes

use nqp;

my role Encoding {
    method decoder { ... }
    method max-bytes-per-code { ... }
}

my class Encoding::UTF8 does Encoding {
    method max-bytes-per-code { !!! }
    method decoder { !!! }
}

my class Encoding::Latin1 does Encoding {
    class Decoder {
        has $!bytes;
        has int $!mark;
        has int $!nl-pos;
        has int $!nl-len;

        submethod BUILD {
            $!bytes := buf8.new;
        }

        method reset {
            $!bytes.reallocate(0);
            self.unmark;
        }

        method unmark {
            $!mark = 0;
            $!nl-pos = 0;
            $!nl-len = 0;
        }

        method add-bytes(buf8:D $buf) {
            $!bytes.append($buf);
        }

        method is-continuable {
            $!bytes[*-1] == 0x0D;
        }

        method available-bytes {
            $!bytes.elems;
        }

        method available-codes {
            $!bytes.elems;
        }

        method available-graphs {
            my int $n = $!bytes.elems;
            loop (my int $i = 1; $i < $n; $i = $i + 1) {
                $n = $n - 1
                    if $!bytes[$i-1] == 0x0D && $!bytes[$i] == 0x0A;
            }

            $n;
        }

        method consume-byte {
            die 'underflow' unless $!bytes;
            $!bytes.splice(0, 1)[0];
        }

        method consume-code {
            die 'underflow' unless $!bytes;
            $!bytes.splice(0, 1)[0];
        }

        method consume-graph {
            given $.available-graphs {
                when 0 { die 'underflow' }
                when 1 {
                    LEAVE $!bytes.reallocate(0);
                    chr $!bytes[0];
                }
                default {
                    if $!bytes[0] == 0x0D && $!bytes[1] == 0x0A {
                        $!bytes.splice(0, 2);
                        "\r\n";
                    }
                    else { chr $!bytes.splice(0, 1)[0] }
                }
            }
        }

        method consume-bytes(uint $n) {
            die 'underflow' if $n > $.available-bytes;
            $!bytes.splice(0, $n);
        }

        method consume-codes(uint $n) {
            die 'underflow' if $n > $.available-codes;
            Uni.new(|$!bytes.splice(0, $n));
        }

        method consume-graphs(uint $n) {
            die 'underflow' if $n > $.available-graphs;
            my int $len = $n;
            loop (my int $i = 1; $i < $n; $i = $i + 1) {
                $len = $len + 1
                    if $!bytes[$i-1] == 0x0D && $!bytes[$i] == 0x0A;
            }
            nqp::strfromcodes(blob32.new(|$!bytes.splice(0, $len)));
        }

        method consume-all-bytes {
            LEAVE $!bytes := buf8.new;
            $!bytes || Nil;
        }

        method consume-all-codes {
            my $codes;
            my int $len = nqp::elems($!bytes);
            nqp::if($len,
                nqp::stmts(
                    nqp::splice(
                        ($codes := nqp::create(Uni)),
                        $!bytes.splice(0),
                        0, 0
                    ),
                    $codes
                ),
                Nil
            );
        }

        method consume-all-graphs {
            my $buf;
            nqp::if(nqp::elems($!bytes),
                nqp::stmts(
                    ($buf := buf32.new),
                    nqp::splice($buf, $!bytes, 0, 0),
                    nqp::setelems($!bytes, 0),
                    nqp::strfromcodes($buf)),
                Nil);
        }

        method consume-line-bytes($chomp) {
            return Nil if $!nl-pos == 0 && $!nl-len == 0;

            my $line;
            if $chomp {
                $line := $!bytes.splice(0, $!nl-pos);
                $!bytes.splice(0, $!nl-len) if $!nl-len;
            }
            else {
                $line := $!bytes.splice(0, $!nl-pos + $!nl-len)
            }
            
            self.unmark;
            $line;
        }

        method consume-line-codes($chomp) {
            my $bytes := self.consume-line-bytes($chomp);
            if $bytes.DEFINITE {
                my $codes := nqp::create(Uni);
                nqp::splice($codes, $bytes, 0, 0);
                $codes;
            }
            else { Nil }
        }

        method consume-line-graphs($chomp) {
            my $bytes := self.consume-line-bytes($chomp);
            $bytes.DEFINITE ?? nqp::strfromcodes(blob32.new(|$bytes)) !! Nil;
        }

        method mark-line($nl) {
            my int $pos = $!mark;
            my int $nl-len = $nl.elems;
            my int $len = $!bytes.elems - $nl-len;
            while $pos <= $len {
                #if $!bytes[$pos..^$pos+$nl-len] eqv $nl[0..*] {
                if $!bytes[$pos] == $nl[0] {
                    $!nl-pos = $pos;
                    $!nl-len = $nl.elems;
                    return True;
                }
                $pos = $pos + 1;
            }

            $!mark = $pos;
            False;
        }
    }

    method max-bytes-per-code { 1 }

    method decoder() { Decoder.new(|%_) }
}

my constant Path = IO::Path;

my %ENCODINGS =
    'utf8' => Encoding::UTF8,
    'latin1' => Encoding::Latin1;

my role IO { ... }

my class IO::Handle {
    has $.encoding;
    has $.decoder;
    has $.block-size;
    has $.nl-out-bytes;
    has $.nl-in-code;
    has $.chomp;

    submethod BUILD(
            :$enc = Encoding::UTF8,
            :$!block-size = 512,
            :$!chomp = True
    ) {
        $!encoding = do given $enc {
            when Encoding { $enc }
            when %ENCODINGS{$enc}:exists { %ENCODINGS{$enc} }
            default { die "unsupported encoding '$enc'" }
        }

        $!decoder = $!encoding.decoder(|%_);

        $!nl-out-bytes = BEGIN blob8.new(0x0A);
        $!nl-in-code = BEGIN blob32.new(0x0A);
    }

    sub unsupported(&method) is hidden-from-backtrace {
        die "IO operation {&method.name} not supported by {::?CLASS.^name}";
    }

    method OPEN     { unsupported &?ROUTINE }
    method CLOSE    { unsupported &?ROUTINE }
    method READ     { unsupported &?ROUTINE }
    method READALL  { unsupported &?ROUTINE }
    method WRITE    { unsupported &?ROUTINE }
    method PUTBYTE  { unsupported &?ROUTINE }
    method PUTCODE  { unsupported &?ROUTINE }

    method NEED-BYTES($n) {
        my $missing := $n - $!decoder.available-bytes;
        if $missing > 0 {
            my $size := $missing max $!block-size;
            $!decoder.add-bytes($_) with self.READ($size);
        }
    }

    method NEED-CODES($n) {
        my $missing := $n - $!decoder.available-codes;
        if $missing > 0 {
            my $size := $missing * $!encoding.max-bytes-per-code max $!block-size;
            $!decoder.add-bytes($_) with self.READ($size);
        }
    }

    method NEED-GRAPHS($n) {
        while (my $missing := $n - $!decoder.available-graphs) > 0
                || ($missing == 0 && $!decoder.is-continuable) {
            my $size := $missing * $!encoding.max-bytes-per-code max $!block-size;
            $!decoder.add-bytes(self.READ($size) // last);
        }
    }

    method NEED-LINE {
        $!decoder.unmark;
        until $!decoder.mark-line($!nl-in-code) {
            $!decoder.add-bytes(self.READ($!block-size) // last);
        }
    }

    method close(--> True) {
        $!decoder.reset;
        self.CLOSE;
    }

    method read(UInt:D $n --> blob8:D) {
        self.NEED-BYTES($n);
        $!decoder.consume-bytes($n);
    }

    method readline(--> blob8:D) {
        self.NEED-LINE;
        $!decoder.consume-line-bytes($!chomp);
    }

    method readall(--> blob8:D) {
        $!decoder.add-bytes(self.READALL);
        $!decoder.consume-all-bytes;
    }

    method write(blob8:D $bytes --> True) {
        self.WRITE($bytes);
    }

    method getbyte(--> uint8) {
        self.NEED-BYTES(1);
        $!decoder.consume-byte;
    }

    method putbyte(uint8 $byte --> True) {
        self.PUTBYTE($byte);
    }

    method uniread(UInt:D $n --> Uni:D) {
        self.NEED-CODES($n);
        $!decoder.consume-codes($n);
    }

    method unireadall(--> Uni:D) {
        $!decoder.add-bytes(self.READALL);
        $!decoder.consume-all-codes;
    }

    method uniwrite(Uni:D $uni --> True) {
        self.WRITE($!encoding.encode($uni));
    }

    method uniget(--> Uni:D) {
        self.NEED-LINE;
        $!decoder.consume-line-codes($!chomp);
    }

    method unigetc(--> uint32) {
        self.NEED-CODES(1);
        $!decoder.consume-code;
    }

    method uniput(Uni:D $uni --> True) {
        self.WRITE($!encoding.encode($uni));
        self.WRITE($!nl-out-bytes);
    }

    method uniputc(uint32 $cp --> True) {
        self.WRITE($!encoding.encode($cp));
    }

    method readchars(UInt:D $n --> Str:D) {
        self.NEED-GRAPHS($n);
        $!decoder.consume-graphs($n);
    }

    method readallchars(--> Str:D) {
        $!decoder.add-bytes(self.READALL);
        $!decoder.consume-all-graphs;
    }

    method print(Str:D $str --> True) {
        self.WRITE($!encoding.encode($str));
    }

    method print-nl(--> True) {
        self.WRITE($!nl-out-bytes);
    }

    method get(--> Str:D) {
        self.NEED-LINE;
        $!decoder.consume-line-graphs($!chomp);
    }

    method getc(--> Str:D) {
        self.NEED-GRAPHS(1);
        $!decoder.consume-graph;
    }

    method put(Str:D $str --> True) {
        self.WRITE($!encoding.encode($str));
        self.WRITE($!nl-out-bytes);
    }
}

my role IO[IO::Handle:U \HANDLE] {
    method open(--> IO::Handle:D) {
        my \handle = HANDLE.new(io => self, |%_);
        handle.OPEN(|%_);
        handle;
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

    proto method lines {*}
    multi method lines(:$bin! --> Seq:D) {
        my \handle = self.open(|%_);
        Seq.new(nqp::create(class :: does Iterator {
            method pull-one() is raw {
                handle.readline // do {
                    handle.close;
                    IterationEnd
                }
            }

            method push-all(\target --> IterationEnd) {
                my $line;
                target.push($line) while ($line := handle.readline).DEFINITE;
                handle.close;
            }
        }));
    }
    multi method lines(:$uni! --> Seq:D) {
        my \handle = self.open(|%_);
        Seq.new(nqp::create(class :: does Iterator {
            method pull-one() is raw {
                handle.uniget // do {
                    handle.close;
                    IterationEnd
                }
            }

            method push-all(\target --> IterationEnd) {
                my $line;
                target.push($line) while ($line := handle.uniget).DEFINITE;
                handle.close;
            }
        }));
    }
    multi method lines(--> Seq:D) {
        my \handle = self.open(|%_);
        Seq.new(nqp::create(class :: does Iterator {
            method pull-one() is raw {
                handle.get // do {
                    handle.close;
                    IterationEnd
                }
            }

            method push-all(\target --> IterationEnd) {
                my $line;
                target.push($line) while ($line := handle.get).DEFINITE;
                handle.close;
            }
        }));
    }
}

my class IO::FileHandle is IO::Handle {
    has $!fh;
    has $!path;

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

    submethod BUILD(:$io) {
        $!path = $io.abspath;
    }

    method fd(--> int) {
        nqp::filenofh($!fh);
    }

    method OPEN {
        $!fh := nqp::open($!path, mode(|%_));
    }

    method CLOSE {
        nqp::closefh($!fh);
    }

    method READ(Int:D \n --> blob8:D) {
        nqp::readfh($!fh, buf8.new, nqp::unbox_i(n)) || Nil;
    }

    method READALL(--> blob8:D) {
        my \buf = buf8.new;
        my $chunk;
        nqp::while(
            nqp::elems($chunk := nqp::readfh($!fh, buf8.new, 0x100000)),
            nqp::splice(buf, $chunk, nqp::elems(buf), 0));
        buf;
    }

    method WRITE(blob8:D \buf --> True) {
        nqp::writefh($!fh, buf);
    }
}

my class IO::Path is Path does IO[IO::FileHandle] {}

sub EXPORT { BEGIN Map.new((NewIO => IO)) }
