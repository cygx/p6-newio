use lib '.';
use NewIO;

say IO::Path.new('.gitignore').open.readall.decode;
