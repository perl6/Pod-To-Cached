# assumes that there are directories REP and DOC left from tests in 040
use lib 'lib';
use Test;
use Test::Output;
use Pod::To::Cached;
use File::Directory::Tree;
use File::Temp;

constant TMP = tempdir;
constant REP = TMP ~ '/ref';
constant DOC = 't/doctest';

my $cache;
lives-ok {
    $cache = Pod::To::Cached.new( :source( DOC ), :path( REP ), :!verbose)
    }, "created cache";
lives-ok {
    $cache.update-cache
}, "update cache";

ok (REP).IO.d;

done-testing;
