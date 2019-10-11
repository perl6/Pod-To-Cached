use lib 'lib';
use Test;
use Pod::To::Cached;
use File::Directory::Tree;

plan *;

constant REP = 't/tmp/ref-ignore';
constant DOC = 't/tmp/doc-ignore';
constant IGNORE_FILE = ".cache-ignore";

mkdir DOC.IO;

my Pod::To::Cached $cache;
diag 'Test .cache-ignore file';

DOC.IO.add('test1.pod6').spurt(q:to/CONTENT/);
    =begin pod
    =end pod
CONTENT

DOC.IO.add('test2.pod6').spurt(q:to/CONTENT/);
    =begin pod
    =end pod
CONTENT

#--MARKER-- Test 1
$cache .= new( :source( DOC ), :path( REP ), :!verbose);
is-deeply $cache.get-pods.sort.map({.IO}),
          ("t/tmp/doc-ignore/test1.pod6".IO,
           "t/tmp/doc-ignore/test2.pod6".IO),
          IGNORE_FILE ~ " does not exist";

#--MARKER-- Test 2
IGNORE_FILE.IO.spurt("");
$cache .= new( :source( DOC ), :path( REP ), :!verbose);
is-deeply $cache.get-pods.sort.map({.IO}),
          ("t/tmp/doc-ignore/test1.pod6".IO,
           "t/tmp/doc-ignore/test2.pod6".IO),
          IGNORE_FILE ~ " is empty";
unlink IGNORE_FILE;

#--MARKER-- Test 3
IGNORE_FILE.IO.spurt("test2");
$cache .= new( :source( DOC ), :path( REP ), :!verbose);
is-deeply $cache.get-pods.sort.map({.IO}),
          ("t/tmp/doc-ignore/test1.pod6".IO,),
          IGNORE_FILE ~ " with simple regex";
unlink IGNORE_FILE;

rmtree REP;
rmtree DOC;