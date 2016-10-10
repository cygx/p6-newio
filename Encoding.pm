no precompilation;
use nqp;

sub has-unique-decomposition($_) {
    .NFC == .NFD && [==] .NFC.map: {
        nqp::getuniprop_int($_, BEGIN nqp::unipropcode('ccc'));
    }
}

my role Encoding { ... }

my role Encoding::Decoder {}

my role Encoding::Decoder::Generic8[$] { ... }
my role Encoding::Decoder::Generic16[$] { ... }
my role Encoding::Decoder::Generic32[$] { ... }

my role Encoding[Int:D \UNIT-BITS, Int:D \MAX-UNITS = 32 div UNIT-BITS] {
    my \UNIT-BYTES = UNIT-BITS div 8;

    method units-for-codepoint(uint32 --> Int:D) { ... }

    method bytes-for-uni(Uni:D \uni --> Int:D) {
        uni.map({ self.units-for-code($_) }).sum * UNIT-BYTES;
    }

    method encode-codepoint(uint32 \cp, Buf \buf, int $offset is rw --> Nil) {
        ...
    }

    method encode-uni(Uni:D \uni --> blob8:D) {
        my \buf = buf8.allocate(uni.elems * MAX-UNITS);
        my int $i = 0;
        self.encode-codepoint($_, buf, $i) for uni;
        buf.reallocate($i);
    }

    proto method encode-str(Str:D \str --> blob8:D) { self.encode-uni({*}, |%_) }
    multi method encode-str(Str:D \str, :$NFC!  --> blob8:D) { str.NFC }
    multi method encode-str(Str:D \str, :$NFD!  --> blob8:D) { str.NFD }
    multi method encode-str(Str:D \str, :$NFKC! --> blob8:D) { str.NFKC }
    multi method encode-str(Str:D \str, :$NFKD! --> blob8:D) { str.NFKD }
    multi method encode-str(Str:D \str          --> blob8:D) { str.NFC }

    method decoder(--> Encoding::Decoder:D) {
        given UNIT-BITS {
            when 8 { Encoding::Decoder::Generic8[self].new(|%_) }
            when 16 { Encoding::Decoder::Generic16[self].new(|%_) }
            when 32 { Encoding::Decoder::Generic32[self].new(|%_) }
            default { !!! }
        }
    }
}

my role Encoding::Decoder::Generic8[Encoding \ENC] does Encoding::Decoder {
    has $.bytes = buf8.new;
    has @.separators;

    method encoding { ENC }

    method new(:$sep = ("\n", "\r", "\r\n")) {
        my \decoder = self.bless;
        decoder.set-line-separators($sep.list);
        decoder;
    }

    method reset(--> Nil) {
        $!bytes = buf8.new;
    }

    method set-line-separators(@seps --> Nil) {
        @!separators = @seps.map: {
            when Str {
                if .&has-unique-decomposition { ENC.encode-codes(.NFC, |%_) }
                else {
                    warn qq:to/END/;
    Separator {.perl} has ambiguous codepoint decomposition - falling back to
    NFC and NFD variants.

    To silence the warning, either provide manual decompositions as Uni instead
    of Str or use &split.
    END
                    slip ENC.encode-codes(.NFC, |%_),
                         ENC.encode-codes(.NFD, |%_);
                }
            }
            when Uni { ENC.encode-codes($_, |%_) }
            when blob8 { $_ }
            default { die "cannot use {.perl} as separator" }
        }
    }

    method add-bytes(blob8:D $bytes --> Nil) {
        $!bytes.append($bytes);
    }

    method consume-all-bytes(--> blob8:D) {
        LEAVE self.reset;
        $!bytes;
    }
}

my role Encoding::Decoder::Generic16[$] does Encoding::Decoder {}
my role Encoding::Decoder::Generic32[$] does Encoding::Decoder {}

my class Encoding::UTF8 does Encoding[8] {
    method units-for-codepoint(uint32 $_ --> Int:D) {
        when $_ <= 0x7F     { 1 }
        when $_ <= 0x7FF    { 2 }
        when $_ <= 0xFFFF   { 3 }
        when $_ <= 0x1FFFFF { 4 }
        default { !!! }
    }

    method encode-codepoint(uint32 $_, Buf \buf, int $offset is rw --> Nil) {
        when $_ <= 0x7F {
            nqp::bindpos_i(buf, $offset, $_);
            $offset = $offset + 1;
        }

        when $_ <= 0x7FF {
            nqp::bindpos_i(buf, $offset,     0xC0 +| ($_ +> 6));
            nqp::bindpos_i(buf, $offset + 1, 0x80 +| ($_ +& 0x3F));
            $offset = $offset + 2;
        }

        when $_ <= 0xFFFF {
            nqp::bindpos_i(buf, $offset,     0xE0 +|  ($_ +> 12));
            nqp::bindpos_i(buf, $offset + 1, 0x80 +| (($_ +>  6) +& 0x3F));
            nqp::bindpos_i(buf, $offset + 2, 0x80 +| ( $_        +& 0x3F));
            $offset = $offset + 3;
        }

        when $_ <= 0x1FFFFF {
            nqp::bindpos_i(buf, $offset,     0xF0 +|  ($_ +> 18));
            nqp::bindpos_i(buf, $offset + 1, 0x80 +| (($_ +> 12) +& 0x3F));
            nqp::bindpos_i(buf, $offset + 2, 0x80 +| (($_ +>  6) +& 0x3F));
            nqp::bindpos_i(buf, $offset + 3, 0x80 +| ( $_        +& 0x3F));
            $offset = $offset + 4;
        }

        default { !!! }
    }
}

sub EXPORT { BEGIN Map.new((Encoding => Encoding)) }
