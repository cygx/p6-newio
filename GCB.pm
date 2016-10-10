no precompilation;
use nqp;

unit module GCB;

enum Property <
    Other
    Control CR LF
    L V T LV LVT
    Prepend Extend SpacingMark ZWJ Glue_After_Zwj
    E_Base E_Base_GAZ E_Modifier Regional_Indicator
>;

my constant PCOUNT = +Property::;
my constant TABLE = do {
    my @table[PCOUNT;PCOUNT] = (True xx PCOUNT) xx PCOUNT;
    @table[CR;LF] = False;
    @table[L;$_] = False for L, V, LV, LVT;
    @table[$_;T] = False for V, T, LV, LVT;
    @table[$_;V] = False for V, LV;
    @table[$_;Extend] = False for Property::.values;
    @table[$_;ZWJ] = False for Property::.values;
    @table[$_;SpacingMark] = False for Property::.values;
    @table[Prepend;$_] = False for Property::.values;
    @table[$_;E_Modifier] = False for E_Base, E_Base_GAZ, Extend;
    @table[ZWJ;$_] for Glue_After_Zwj, E_Base_GAZ;
    @table[Regional_Indicator;Regional_Indicator] = False;
    @table;
}

our sub get-property(uint32 \code) {
    Property::{nqp::getuniprop_str(code, BEGIN nqp::unipropcode('gcb'))};
}

our sub is-break(uint32 \a, uint32 \b) {
    TABLE[get-property(a);get-property(b)];
}

our sub is-potential-break(uint32 \a, uint32 \b) {
    my \pa = get-property(a);
    my \pb = get-property(b);
    TABLE[pa;pb] || (pa == Extend && pb == E_Modifier)
                 || (pa == pb == Regional_Indicator);
}

our sub clusters(Uni \uni) {
    return uni if uni.elems < 2;
    my $emoji = False;
    my $ri = False;
    my int $i = 0;
    my int $j = 0;
    gather {
        while ++$j < uni.elems {
            my \pa = get-property(uni[$j-1]);
            my \pb = get-property(uni[$j]);
            if TABLE[pa;pb]
                    || (!$emoji && (pa == Extend && pb == E_Modifier))
                    || ($ri && pa == pb == Regional_Indicator) {
                take Uni.new(uni[$i..^$j]);
                $i = $j;
                $emoji = False;
                $ri = False;
            }
            else {
                $emoji = True if pa == any(E_Base, E_Base_GAZ);
                $ri = True if pa == pb == Regional_Indicator;
            }
        }
        take Uni.new(uni[$i..^$j]);
    }
}
