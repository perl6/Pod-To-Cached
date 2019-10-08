use lib 'lib';
use Test;
use Pod::To::Cached;
use File::Directory::Tree;

plan *;

constant REP = 't/tmp/ref-ignore';
constant DOC = 't/tmp/doc-ignore';
constant IGNORE_FILE = ".cache-ignore";

mkdir DOC;

my Pod::To::Cached $cache;
diag 'Test .cache-ignore file';

create-pods("test1.pod6");
create-pods("test2.pod6");

#--MARKER-- Test 1
$cache .= new( :source( DOC ), :path( REP ), :verbose);
is-deeply $cache.get-pods, 
          ["t/tmp/doc-ignore/test2.pod6",
           "t/tmp/doc-ignore/test1.pod6"],
          IGNORE_FILE ~ " does not exist";

#--MARKER-- Test 2
IGNORE_FILE.IO.spurt("");
$cache .= new( :source( DOC ), :path( REP ), :verbose);
is-deeply $cache.get-pods, 
          ["t/tmp/doc-ignore/test2.pod6",
           "t/tmp/doc-ignore/test1.pod6"],
          IGNORE_FILE ~ " is empty";
unlink IGNORE_FILE;

#--MARKER-- Test 3
IGNORE_FILE.IO.spurt("test2");
$cache .= new( :source( DOC ), :path( REP ), :verbose);
is-deeply $cache.get-pods, 
          ["t/tmp/doc-ignore/test2.pod6"],
          IGNORE_FILE ~ " with simple regex";
unlink IGNORE_FILE;

rmtree REP;
rmtree DOC;

# helpers

sub create-pods($filename) {
(DOC ~ "/$filename").IO.spurt(q:to/POD-CONTENT/);
    =begin pod
    =TITLE More and more
    =end pod
    POD-CONTENT
}