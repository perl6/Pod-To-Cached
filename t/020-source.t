use lib 'lib';
use Test;
use Test::Output;
use File::Directory::Tree;
use JSON::Fast;
use Pod::To::Cached;

constant REP = 't/tmp/ref';
constant DOC = 't/tmp/doc';
constant INDEX = REP ~ '/file-index.json';

plan 28;

my Pod::To::Cached $cache;

mktree DOC;
#--MARKER-- Test 1
throws-like { $cache .= new( :source( DOC ), :path( REP ) ) },
    Exception, :message(/'No POD files found under'/), 'Detects absence of source files';

(DOC ~ '/a-pod-file.pod6').IO.spurt(q:to/POD-CONTENT/);
    =pod A test file
    =TITLE This is a title

    Some text

    =end pod
    POD-CONTENT

(DOC ~ '/a-second-pod-file.pod6').IO.spurt(q:to/POD-CONTENT/);
    =pod Another test file
    =TITLE More and more

    Some more text

    =end pod
    POD-CONTENT
# Change the extension but not the name
(DOC ~ '/a-second-pod-file.pod').IO.spurt(q:to/POD-CONTENT/);
    =pod Another test file
    =TITLE More and more

    Some more text

    =end pod
    POD-CONTENT

#--MARKER-- Test 2
throws-like { $cache .= new( :source( DOC ), :path( REP ))},
    Exception, :message(/'duplicates name of'/), 'Detects duplication of source file names';

(DOC ~ '/a-second-pod-file.pod').IO.unlink ;
#--MARKER-- Test 3
nok REP.IO ~~ :d, 'No cache directory should be created yet';
#--MARKER-- Test 4
lives-ok { $cache .= new( :source( DOC ), :path( REP ), :!verbose) }, 'Instantiates OK';
#--MARKER-- Test 5
ok REP.IO ~~ :d, 'Correctly creates the cache directory';
#--MARKER-- Test 6
ok INDEX.IO ~~ :f, 'index file has been created';
my %config;
#--MARKER-- Test 7
lives-ok { %config = from-json( INDEX.IO.slurp ) }, 'good json in index';
#--MARKER-- Test 8
ok (%config<frozen>:exists and %config<frozen> ~~ 'False'), 'frozen is False as expected';
#--MARKER-- Test 9
ok (%config<files>:exists
    and %config<files>.WHAT ~~ Hash)
    , 'files is as expected';
#--MARKER-- Test 10
is +%config<files>.keys, 0, 'No source files in index because nothing in cache';

my $mod-time = INDEX.IO.modified;
my $rv;
#--MARKER-- Test 11
lives-ok {$rv = $cache.update-cache}, 'Updates cache without dying';
#--MARKER-- Test 12
nok $rv, 'Returned false because of compile errors';
#--MARKER-- Test 13
like $cache.error-messages[0], /'Compile error in'/, 'Error messages saved';
#--MARKER-- Test 14
is-deeply $cache.list-files( :all ), ( 'a-pod-file' => 'Failed', 'a-second-pod-file'=>'Failed').hash, 'lists Failed files';
#--MARKER-- Test 15
nok INDEX.IO.modified > $mod-time, 'INDEX not modified';
#--MARKER-- Test 16
is +gather for $cache.files.kv -> $nm, %inf { take 'f' unless %inf<handle>:exists },
    2, 'No handles are defined for Failed files';

$cache.verbose = True;
#--MARKER-- Test 17
stderr-like { $cache.update-cache }, /'Cache not fully updated'/, 'Got correct progress message';
$cache.verbose = False;

(DOC ~ '/a-pod-file.pod6').IO.spurt(q:to/POD-CONTENT/);
    =begin pod
    =TITLE This is a title

    Some text

    =end pod
    POD-CONTENT

(DOC ~ '/a-second-pod-file.pod6').IO.spurt(q:to/POD-CONTENT/);
    =begin pod
    =TITLE More and more

    Some more text

    =end pod
    POD-CONTENT

#--MARKER-- Test 18
ok $cache.update-cache, 'Returned true because both POD now compile';
# this works because the source paths are in the cache object, and they are new

#--MARKER-- Test 19
is-deeply $cache.list-files( :all ), ( 'a-pod-file' => 'Current', 'a-second-pod-file'=>'Current').hash, 'list-files shows two pod Current';

#--MARKER-- Test 20
ok INDEX.IO.modified > $mod-time, 'INDEX has been modified because update cache ok';

(DOC ~ '/a-second-pod-file.pod6').IO.spurt(q:to/POD-CONTENT/);
    =begin pod
    =TITLE More and more

    Some more text but now it is changed

    =end pod
    POD-CONTENT
$cache .= new( :source( DOC ), :path( REP ));
#--MARKER-- Test 21
is-deeply $cache.list-files( :all ), ( 'a-pod-file' => 'Current', 'a-second-pod-file'=>'Valid').hash, 'One current, one tainted';
#--MARKER-- Test 22
is-deeply $cache.list-files( <Valid Current> ), ( 'a-pod-file' , 'a-second-pod-file', ), 'List with list of statuses';
$cache.update-cache;
#--MARKER-- Test 23
is-deeply $cache.list-files( :all ), ( 'a-pod-file' => 'Current', 'a-second-pod-file'=>'Current').hash, 'Both updated';

#has an error
(DOC ~ '/a-pod-file.pod6').IO.spurt(q:to/POD-CONTENT/);
    =pod A test file
    =TITLE This is a title

    Some text

    =end pod
    POD-CONTENT

$cache .= new( :source( DOC ), :path( REP ));
#--MARKER-- Test 24
is-deeply $cache.list-files( :all ), ( 'a-pod-file' => 'Valid', 'a-second-pod-file'=>'Current').hash, 'One current, one tainted';
$cache.update-cache;
#--MARKER-- Test 25
is-deeply $cache.list-files( :all ), ( 'a-pod-file' => 'Valid', 'a-second-pod-file'=>'Current').hash, 'One remains Valid because new version did not compile';
#--MARKER-- Test 26
like $cache.error-messages.join, /'Compile error'/, 'Error detected in pod';

# return to valid pod;
(DOC ~ '/a-pod-file.pod6').IO.spurt(q:to/POD-CONTENT/);
    =begin pod
    =TITLE This is a title

    Some text

    =end pod
    POD-CONTENT

#--MARKER-- Test 27
lives-ok {$cache .=new(:path( REP ))}, 'with a valid cache, source can be omitted';
$cache.update-cache;
#--MARKER-- Test 28
is-deeply $cache.list-files( :all ), ( 'a-pod-file' => 'Current', 'a-second-pod-file'=>'Current').hash, 'Both Current now';
