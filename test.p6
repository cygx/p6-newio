no precompilation;
use lib '.';
use Encoding;

my \buf = Encoding::Buf.new;
buf.add(blob8.new(1, 2, 3));
buf.add(Encoding::Buf::DENORMAL);
buf.add(blob16.new(4, 5, 6));
buf.say;
