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

my role Encoding[Int:D \UNIT-BITS] {
    method unit-bits(--> Int:D) { UNIT-BITS }

    method decoder(--> Encoding::Decoder:D) {
        given UNIT-BITS {
            when 8 { Encoding::Decoder::Generic8[self].new(|%_) }
            when 16 { Encoding::Decoder::Generic16[self].new(|%_) }
            when 32 { Encoding::Decoder::Generic32[self].new(|%_) }
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
    method encode-codes(Uni:D \uni --> blob8:D) {
        my \buf = buf8.allocate(uni.elems * 4);
        my int $i = 0;
        for uni {
            when $_ <= 0x7F {
                nqp::bindpos_i(buf, $i++, $_);
            }

            when $_ <= 0x7FF {
                nqp::bindpos_i(buf, $i++, 0xC0 +| ($_ +> 6));
                nqp::bindpos_i(buf, $i++, 0x80 +| ($_ +& 0x3F));
            }

            when $_ <= 0xFFFF {
                nqp::bindpos_i(buf, $i++, 0xE0 +|  ($_ +> 12));
                nqp::bindpos_i(buf, $i++, 0x80 +| (($_ +>  6) +& 0x3F));
                nqp::bindpos_i(buf, $i++, 0x80 +| ( $_        +& 0x3F));
            }

            when $_ <= 0x1FFFFF {
                nqp::bindpos_i(buf, $i++, 0xF0 +|  ($_ +> 18));
                nqp::bindpos_i(buf, $i++, 0x80 +| (($_ +> 12) +& 0x3F));
                nqp::bindpos_i(buf, $i++, 0x80 +| (($_ +>  6) +& 0x3F));
                nqp::bindpos_i(buf, $i++, 0x80 +| ( $_        +& 0x3F));
            }

            default { !!! }
        }

        buf.reallocate($i);
    }
}

sub EXPORT { BEGIN Map.new((Encoding => Encoding)) }
