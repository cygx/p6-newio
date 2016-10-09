use nqp;

# valid 'byte' patterns:
#   B 1b 2bb - base char
#   C 1c 2cc - combining char
#   S 1s 2ss - standalone char
#   R - CR
#   N - LF

# TODO:
# method set-line-separators(@seps --> Nil)
# method consume-line-chars(Bool :$chomp = False, Bool :$oef = False --> Str)

sub is-break($a, $b) {
    my $ab = $a ~ $b;
    not $ab eq 'RN' || ($a ~~ /:i b|c/ && $b ~~ /:i c/);
}

sub cannot-combine($_) {
    so /:i s|n/;
}

# combining class 0
sub is-base($_) {
    not /:i c/;
}

sub bytes-for-code($_) {
    /<:upper>/ ?? 1 !! .chars + 1;
}

class Decoder {
    has @.codes;
    has @.bytes;

    has $.cursor = 0;
    has $.mark = 0;

    has $.code = '';
    has $.todo = 0;

    method is-empty {
        @!bytes == 0;
    }

    method has-undecoded {
        @!bytes > $!mark;
    }

    method reset {
        @!codes = ();
        @!bytes = ();
        $!cursor = 0;
        $!mark = 0;
        $!code = '';
        $!todo = 0;
    }

    method add-bytes(@bytes) {
        @!bytes.append(@bytes);
    }

    method !decode-bytes-to-codes {
        while $!cursor < @!bytes {
            my $byte = @!bytes[$!cursor++];
            if $!todo == 0 {
                given $byte {
                    when any <B C S R N> {
                        @!codes.push($byte);
                        $!mark = $!cursor;
                    }
                    when any('1', '2') { $!todo = +$byte }
                    default { die "illegal header byte '$byte'" }
                }
            }
            else {
                if $byte eq any <b c s> { $!code ~= $byte }
                else { die "illegal trailing byte '$byte'" }

                if --$!todo == 0 {
                    die "illegal code point '$!code'"
                        unless [eq] $!code.comb;

                    @!codes.push($!code);
                    $!mark = $!cursor;
                    $!code = '';
                }
            }
        }
    }

    method !decode-max-n-bytes-to-codes($n) {
        my $i = 0;
        while $!cursor < @!bytes && $i < $n {
            my $byte = @!bytes[$!cursor++];
            if $!todo == 0 {
                given $byte {
                    when any <B C S R N> {
                        @!codes.push($byte);
                        $!mark = $!cursor;
                        ++$i;
                    }
                    when any('1', '2') { $!todo = +$byte }
                    default { die "illegal header byte '$byte'" }
                }
            }
            else {
                if $byte eq any <b c s> { $!code ~= $byte }
                else { die "illegal trailing byte '$byte'" }

                if --$!todo == 0 {
                    die "illegal code point '$!code'"
                        unless [eq] $!code.comb;

                    @!codes.push($!code);
                    $!mark = $!cursor;
                    $!code = '';
                    ++$i;
                }
            }
        }
    }

    method !has-graphs($n is copy) {
        return False unless @!codes;

        my $i = 0;
        while ++$i < @!codes {
            return True if is-break(@!codes[$i-1], @!codes[$i]) && --$n == 0;
        }

        cannot-combine(@!codes[*-1]) && --$n == 0;
    }

    method !normalize-codes-to-graphs($all, $n is rw) {
        return Nil unless  @!codes;

        my @graphs;

        my $i = 1;
        while $i < @!codes {
            if is-break(@!codes[$i-1], @!codes[$i]) {
                my @c := @!codes.splice(0, $i);
                $n += [+] @c.map(&bytes-for-code);
                @graphs.push(@c.join('+'));
                $i = 1;
            }
            else { ++$i }
        }


        if $all || cannot-combine(@!codes[*-1]) {
            my @c := @!codes.splice;
            $n += [+] @c.map(&bytes-for-code);
            @graphs.push(@c.join('+'));
        }

        @graphs;
    }

    method !normalize-max-n-codes-to-graphs($max, $all, $n is rw) {
        return Nil unless  @!codes;

        my @graphs;

        my $i = 1;
        my $j = 0;
        while $i < @!codes && $j < $max {
            if is-break(@!codes[$i-1], @!codes[$i]) {
                my @c := @!codes.splice(0, $i);
                $n += [+] @c.map(&bytes-for-code);
                @graphs.push(@c.join('+'));
                $i = 1;
                ++$j;
            }
            else { ++$i }
        }


        if $all || cannot-combine(@!codes[*-1]) {
            my @c := @!codes.splice;
            $n += [+] @c.map(&bytes-for-code);
            @graphs.push(@c.join('+'));
            ++$j;
        }

        @graphs;
    }

    method !discard-decoded-bytes {
        @!bytes.splice(0, $!mark);
        $!cursor -= $!mark;
        $!mark = 0;
    }

    method !discard-n-decoded-bytes($n) {
        @!bytes.splice(0, $n);
        $!cursor -= $n;
        $!mark -= $n;
    }

    method consume-available-bytes {
        LEAVE self.reset;
        :bytes(|@!bytes);
    }

    method consume-available-codes {
        LEAVE self!discard-decoded-bytes;
        self!decode-bytes-to-codes;
        @!codes ?? :codes(|@!codes) !! Nil;
    }

    method consume-available-graphs {
        self!decode-bytes-to-codes;
        my @graphs := self!normalize-codes-to-graphs(False, my $n = 0);
        @!codes ?? self!discard-n-decoded-bytes($n)
                !! self!discard-decoded-bytes;

        @graphs ?? :graphs(|@graphs) !! Nil;
    }

    method consume-all-bytes {
        LEAVE self.reset;
        :bytes(|@!bytes || return Nil);
    }

    method consume-all-codes {
        LEAVE self.reset;
        self!decode-bytes-to-codes;
        die 'incomplete multibyte sequence'
            if self.has-undecoded;

        :codes(|@!codes || return Nil);
    }

    method consume-all-graphs {
        LEAVE self.reset;
        self!decode-bytes-to-codes;
        die 'incomplete multibyte sequence'
            if self.has-undecoded;

        :graphs(|self!normalize-codes-to-graphs(True, my $) || return Nil);
    }

    method consume-bytes($n) {
        @!bytes < $n ?? Nil !! do {
            my @b := @!bytes.splice(0, $n);
            @!codes = ();
            $!cursor = 0;
            $!mark = 0;
            $!code = '';
            $!todo = 0;
            :bytes(|@b);
        }
    }

    method consume-codes($n) {
        if @!codes < $n {
            self!decode-max-n-bytes-to-codes($n - @!codes);
            return Nil if @!codes < $n;
        }

        my @c := @!codes.splice(0, $n);
        self!discard-n-decoded-bytes([+] @c.map(&bytes-for-code));
        :codes(|@c);
    }

    method consume-graphs($n) {
        self!decode-bytes-to-codes;
        return Nil unless self!has-graphs($n);

        my @graphs := self!normalize-max-n-codes-to-graphs($n, True, my $c);
        @!codes ?? self!discard-n-decoded-bytes($c)
                !! self!discard-decoded-bytes;

        @graphs ?? :graphs(|@graphs) !! Nil;
    }
}

my $decoder = Decoder.new;
$decoder.add-bytes('BC2bbC2'.comb);
say $decoder;
say $decoder.consume-graphs(2);
say $decoder;
say $decoder.consume-graphs(1);
say $decoder;
