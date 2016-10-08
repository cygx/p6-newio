use lib '.';
use NewIO;

say IO::Path.^roles;
my \path = IO::Path.new('.gitignore');
say path.open;
