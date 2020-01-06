# assumes that there are directories REP and DOC left from tests in 040
use lib 'lib';
use Test;
use Test::Output;
use Pod::To::Cached;
use File::Directory::Tree;

constant REP = 't/tmp/ref';
constant DOC = 't/doctest';

rmtree REP;
my $cache;
lives-ok {
    $cache = Pod::To::Cached.new( :source( DOC ), :path( REP ), :!verbose)
    }, "created cache";
lives-ok {
    $cache.update-cache
}, "update cache";

say $cache.perl;
ok (REP).IO.d;
rmtree REP;

done-testing;
