use lib '.';
use NewIO;

my \N = 200;
my \FILE = 'test.p6';

do {
    my $i = 0;
    my $start = now;
    $i += IO::Path.new(FILE).lines(:enc<latin1>) for ^N;
    my $end = now;
    say $end - $start;
    say $i;
}

do {
    my $i = 0;
    my $start = now;
    $i += NewIO::Path.new(FILE).lines(:enc<latin1>) for ^N;
    my $end = now;
    say $end - $start;
    say $i;
}
