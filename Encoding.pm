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
    has @.bytes = buf8.new;
    has @.separators;

    method encoding { ENC }

    method new(:$sep = ("\n", "\r", "\r\n")) {
        my \decoder = self.bless;
        decoder.set-line-separators($sep.list);
        decoder;
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
}

my role Encoding::Decoder::Generic16[$] does Encoding::Decoder {}
my role Encoding::Decoder::Generic32[$] does Encoding::Decoder {}

my class Encoding::UTF8 does Encoding[8] {
    method encode-codes(Uni:D $to-encode --> blob8:D) {
        !!!
    }
}

sub EXPORT { BEGIN Map.new((Encoding => Encoding)) }
