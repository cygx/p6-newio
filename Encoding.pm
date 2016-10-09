use nqp;

sub is-unique($_) {
    .NFC == .NFD && [==] .NFC.map: {
        nqp::getuniprop_int($_, BEGIN nqp::unipropcode('ccc'));
    }
}

my role Encoding { ... }

my role Encoding::Decoder {}

my class Encoding::Decoder::Generic { ... }

my role Encoding {
    method decoder(*%options --> Encoding::Decoder:D) {
        Encoding::Decoder::Generic.new(self);
    }
}

my class Encoding::Decoder::Generic does Encoding::Decoder {
    has $.encoding;

    method new(Encoding $encoding) {
        self.bless(:$encoding);
    }

    method set-line-separators(@seps --> Nil) {
        @seps.map: {
            when Str {
                warn qq:to/END/ unless is-unique $_;
    Separator {.perl} has ambiguous codepoint decomposition - falling back to
    NFC and NFD variants.

    To silence the warning, either provide manual decompositions as Uni instead
    of Str or use &split.
    END
                # encode .NFC/.NFD
                !!!
            }
            when Uni { !!! }
            when blob8 { $_ }
            default { die "cannot use {.perl} as separator" }
        }
    }

}

my role Encoding::UTF8 does Encoding {}

sub EXPORT { BEGIN Map.new((Encoding => Encoding)) }
