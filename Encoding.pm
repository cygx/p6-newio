use GCB;
use nqp;

my role Encoding { ... }

my class Encoding::Registry {
    my %encodings is default(Nil);

    method add(Encoding \enc, *@aliases --> Nil) {
        %encodings{map &lc, enc.name, @aliases} = enc xx *;
    }

    method get(Str \name) {
        %encodings{name};
    }
}

my role Encoding::Encoder {}
my role Encoding::Decoder {}

my role Encoding::Decoder::Strict[\ENC] { ... }
my role Encoding::Decoder::Warn[\ENC] { ... }
my role Encoding::Decoder::Lax[\ENC] { ... }
my role Encoding::Decoder::Compat[\ENC] { ... }

my enum Encoding::DecoderRV <OK INVALID OVERLONG>;

my role Encoding[Str $name, int :$unit = 1, int :$factor = 1] {
    method name(--> Str) { $name }
    method unit-size(--> int) { $unit }
    method factor(--> int) { $factor }

    method encode(uint32 $cp, \buf, int $pos --> int) { ... }

    method decode(uint32 $cp is rw, \buf, int $pos, int $more is rw)
        returns Encoding::DecoderRV { ... }

    method decode-rest(uint32 $cp is rw, \buf, int $pos)
        returns Encoding::DecoderRV { die }

    method encoder(--> Encoding::Encoder) { die "TODO" }

    proto method decoder(--> Encoding::Decoder) {*}
    multi method decoder(:$strict!) { Encoding::Decoder::Strict[self].new(|%_) }
    multi method decoder(:$compat!) { Encoding::Decoder::Compat[self].new(|%_) }
    multi method decoder(:$lax!) { Encoding::Decoder::Lax[self].new(|%_) }
    multi method decoder(:$warn?) { Encoding::Decoder::Warn[self].new(|%_) }
}

my class Encoding::Latin1 does Encoding['Latin-1'] {
    proto method encode(| --> int) {*}
    multi method encode(uint32 $cp where $cp > 0xFF, $, int $) { 0 }
    multi method encode(uint32 $cp, \buf, int $pos --> 1) {
        nqp::bindpos_i(buf, $pos, $cp);
    }

    method decode(uint32 $cp is rw, \buf, int $pos, int $ is rw --> OK) {
        $cp = nqp::atpos_i(buf, $pos);
    }
}

my class Encoding::UCS2LE does Encoding['UCS2-LE', :unit(2)] {
    proto method encode(| --> int) {*}
    multi method encode(uint32 $cp where $cp > 0xFFFF, $, int $) { 0 }
    multi method encode(uint32 $cp, \buf, int $pos --> 2) {
        nqp::bindpos_i(buf, $pos, $cp +& 0xFF);
        nqp::bindpos_i(buf, $pos + 1, $cp +> 8);
    }

    method decode(uint32 $cp is rw, \buf, int $pos, int $ is rw --> OK) {
        $cp = nqp::atpos_i(buf, $pos)
           +| nqp::atpos_i(buf, $pos + 1) +< 8;
    }
}

my class Encoding::UTF8 does Encoding['UTF-8', :factor(4)] {
    method encode(uint32 $cp, \buf, int $i --> int) {
        when $cp <= 0x7F {
            nqp::bindpos_i(buf, $i, $cp);
            1;
        }

        when $cp <= 0x7FF {
            nqp::bindpos_i(buf, $i,     0xC0 +| ($cp +> 6));
            nqp::bindpos_i(buf, $i + 1, 0x80 +| ($cp +& 0x3F));
            2;
        }

        when $cp <= 0xFFFF {
            nqp::bindpos_i(buf, $i,     0xE0 +|  ($cp +> 12));
            nqp::bindpos_i(buf, $i + 1, 0x80 +| (($cp +>  6) +& 0x3F));
            nqp::bindpos_i(buf, $i + 2, 0x80 +| ( $cp        +& 0x3F));
            3;
        }

        when $cp <= 0x1FFFFF {
            nqp::bindpos_i(buf, $i,     0xF0 +|  ($cp +> 18));
            nqp::bindpos_i(buf, $i + 1, 0x80 +| (($cp +> 12) +& 0x3F));
            nqp::bindpos_i(buf, $i + 2, 0x80 +| (($cp +>  6) +& 0x3F));
            nqp::bindpos_i(buf, $i + 3, 0x80 +| ( $cp        +& 0x3F));
            4;
        }

        default { 0 }
    }

    method decode(uint32 $cp is rw, \buf, int $pos, int $more is rw) {
        my int $b = nqp::atpos_i(buf, $pos);

        when $b <= 0x7F {
            $cp = $b;
            OK;
        }

        when $b <= 0xBF { INVALID }

        when $b <= 0xDF {
            $cp = $b +& 0x1F;
            $more = 1;
            OK;
        }

        when $b <= 0xEF {
            $cp = $b +& 0x0F;
            $more = 2;
            OK;
        }

        when $b <= 0xF7 {
            $cp = $b +& 0x07;
            $more = 3;
            OK;
        }

        default { INVALID }
    }

    proto method decode-rest(|) {*}
    multi method decode-rest(uint32 $cp is rw, \buf, int $pos, 1) {
        my int $b = nqp::atpos_i(buf, $pos);
        if $b +& 0xC0 == 0x80 {
            $cp = $cp +< 6 +| ($b +& 0x3F);
            $cp +& 0x0780 ?? OK !! OVERLONG;
        }
        else { INVALID }
    }
    multi method decode-rest(uint32 $cp is rw, \buf, int $pos, 2) {
        my int $b1 = nqp::atpos_i(buf, $pos);
        my int $b2 = nqp::atpos_i(buf, $pos + 1);
        if ($b1 +& 0xC0 == 0x80) && ($b2 +& 0xC0 == 0x80) {
            $cp = $cp +< 12 +| ($b1 +& 0x3F) +< 6
                            +| ($b2 +& 0x3F);
            $cp +& 0xF800 ?? OK !! OVERLONG;
        }
        else { INVALID }
    }
    multi method decode-rest(uint32 $cp is rw, \buf, int $pos, 3) {
        my int $b1 = nqp::atpos_i(buf, $pos);
        my int $b2 = nqp::atpos_i(buf, $pos + 1);
        my int $b3 = nqp::atpos_i(buf, $pos + 2);
        if ($b1 +& 0xC0 == 0x80) && ($b2 +& 0xC0 == 0x80)
                && ($b3 +& 0xC0 == 0x80) {
            $cp = $cp +< 18 +| ($b1 +& 0x3F) +< 12
                            +| ($b2 +& 0x3F) +< 6
                            +| ($b3 +& 0x3F);
            $cp +& 0x1F0000 ?? OK !! OVERLONG;
        }
        else { INVALID }
    }
}

my class X::Encoding is Exception {}
my role X::Encoding::Encode {}
my role X::Encoding::Decode {}

my class X::Encoding::Invalid is X::Encoding does X::Encoding::Decode {
    has $.encoding;
    has $.bytes;

    proto message(|) {*}
    multi method message($enc, $bytes) {
        "Invalid {$enc.name}: "~ $bytes.list.fmt('%02X', ' ').join(' ');
    }
    multi method message {
        self.message($!encoding, $!bytes);
    }
}

my class X::Encoding::Overlong is X::Encoding does X::Encoding::Decode {
    has $.encoding;
    has $.bytes;
    has $.codepoint;

    proto message(|) {*}
    multi method message($enc, $bytes, $cp) {
        "Overlong {$enc.name} for {nqp::getuniname($cp)}: "
            ~ $bytes.list.fmt('%02X', ' ').join(' ');
    }
    multi method message {
        self.message($!encoding, $!bytes, $!codepoint);
    }
}

my role Encoding::Decoder::Generic does Encoding::Decoder {
    has $.buf;
    has $.codes;
    has int $.pos;
    has int $.more;
    has uint32 $.cp;

    method encoding { ... }
    proto method handle($) {*}
    multi method handle(OK) {}
    multi method handle(INVALID) { ... }
    multi method handle(OVERLONG) { ... }

    method !init(%args) {
        $!buf := buf8.new;
        $!codes := buf32.new;
        self.?BUILD(|%args);
        self;
    }

    method new {
        nqp::create(self)!init(%_);
    }

    method buf { $!buf.subbuf(0) }

    method last-decoded-bytes {
        my $size := self.encoding.unit-size;
        $!more ?? $!buf.subbuf($!pos - $size, $size + $!more)
               !! $!buf.subbuf($!pos, $size);
    }

    method codes { $!codes.subbuf(0) }

    method add-bytes(\bytes --> Nil) {
        nqp::splice($!buf, bytes, nqp::elems($!buf), 0);
    }

    method decode(--> Nil) {
        my \ENC = self.encoding;
        my int $N = nqp::elems($!buf);
        loop {
            if $!more {
                last if $!pos + $!more > $N;
                self.handle(ENC.decode-rest($!cp, $!buf, $!pos, $!more));
                $!pos = $!pos + $!more;
                $!more = 0;
            }
            else {
                last if $!pos >= $N;
                self.handle(ENC.decode($!cp, $!buf, $!pos, $!more));
                $!pos = $!pos + ENC.unit-size;
            }
        }
    }
}

my role Encoding::Decoder::Replacing does Encoding::Decoder::Generic {
    has $.replacement-char;
    submethod BUILD(:$!replacement-char = '?') {}
}

my role Encoding::Decoder::Strict[\ENC] does Encoding::Decoder::Generic {
    method encoding { ENC }

    multi method handle(INVALID) {
        die X::Encoding::Invalid.new(
            :encoding(ENC),
            :bytes(self.last-decoded-bytes));
    }

    multi method handle(OVERLONG) {
        die X::Encoding::Overlong.new(
            :encoding(ENC),
            :bytes(self.last-decoded-bytes),
            :codepoint(self.cp));
    }
}

my role Encoding::Decoder::Warn[\ENC] does Encoding::Decoder::Replacing {
    method encoding { ENC }

    multi method handle(INVALID) {
        warn X::Encoding::Invalid.message(ENC, self.last-decoded-bytes);
        note 'TODO: use replacement char';
    }

    multi method handle(OVERLONG) {
        warn X::Encoding::Overlong.message(ENC, self.last-decoded-bytes, self.cp);
    }
}

my role Encoding::Decoder::Lax[\ENC] does Encoding::Decoder::Replacing {
    method encoding { ENC }

    multi method handle(INVALID) {
        note 'TODO: use replacement char';
    }

    multi method handle(OVERLONG) {}
}

my role Encoding::Decoder::Compat[\ENC] does Encoding::Decoder {
    method encoding { ENC }

    multi method handle(INVALID) {
        die 'TODO';
    }

    multi method handle(OVERLONG) {
        die 'TODO';
    }
}

Encoding::Registry.add(Encoding::Latin1, 'latin1');
Encoding::Registry.add(Encoding::UTF8, 'utf8');

sub EXPORT { BEGIN Map.new((Encoding => Encoding)) }
