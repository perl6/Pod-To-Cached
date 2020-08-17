# assumes that there are directories REP and DOC left from tests in 040
use lib 'lib';
use Test;
use Test::Output;
use Pod::To::Cached;
use File::Temp;

constant TMP = tempdir;
constant REP = TMP ~ '/ref';
constant DOC = 't/doctest';

constant COUNT = 3; # number of caches to create

plan 9;

diag "Create multiple ({ COUNT }) caches";

my @caches;

for ^COUNT {
    lives-ok {
        @caches[$_] = Pod::To::Cached.new( :source( DOC ), :path( REP ~ $_ ), :!verbose)
    }, "created cache no $_";
    lives-ok {
        @caches[$_].update-cache
    }, "update cache no $_";
}

for ^COUNT {
    ok (REP ~ $_ ).IO.d
}

done-testing;