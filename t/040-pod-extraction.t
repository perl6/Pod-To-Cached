use lib 'lib';
use Test;
use Test::Output;
use File::Directory::Tree;
use Pod::To::Cached;

constant REP = 't/tmp/ref';
constant DOC = 't/tmp/doc';
constant INDEX = REP ~ '/file-index.json';

plan 15;

my Pod::To::Cached $cache;
my $rv;
diag 'test pod extraction';
$cache .= new( :path( REP ));
#--MARKER-- Test 1
ok $cache.pod('a-pod-file') ~~ Pod::Block::Named, 'pod is returned from cache';

(DOC ~ '/a-second-pod-file.pod6').IO.spurt(q:to/POD-CONTENT/);
    =begin pod
    =TITLE More and more

    Some more text but now it is changed, and again

    =end pod
    POD-CONTENT

$cache .=new(:path( REP ));
my %h = $cache.list-files( :all );
#--MARKER-- Test 2
is %h<a-pod-file>, 'Valid', 'one Valid';
#--MARKER-- Test 3
is %h<a-second-pod-file>, 'Tainted', 'One Valid, not Updated because new instantiation of Pod::To::Cached, one Tainted';
#--MARKER-- Test 4
throws-like { $cache.pod('a-second-pod-file', :when-tainted('exit')) }, Exception,
    :message(/ 'POD called with exit processing'/), 'Pod should fail if tainted behaviour exit';
#--MARKER-- Test 5
is $cache.pod('a-second-pod-file', :when-tainted('none')), Nil, 'Nil return for none';

#--MARKER-- Test 6
stderr-like { $rv = $cache.pod('a-second-pod-file', :when-tainted('note')) }, /'source pod has been modified'/, 'An error message when note';
#--MARKER-- Test 7
ok $rv ~~ Pod::Block::Named, 'pod supplies output for note because previous version still in cache';
#--MARKER-- Test 8
stderr-like {$rv = $cache.pod('a-second-pod-file', :when-tainted('note-none'))}, /'source pod has been modified'/, 'Same error message when note-none';
#--MARKER-- Test 9
nok $rv, 'produces a note, but no POD';

diag 'testing freeze';
#--MARKER-- Test 10
throws-like { $cache.freeze }, Exception, :message(/'Cannot freeze because the following'/), 'Cant freeze when a file is tainted';

#--MARKER-- Test 11
ok $cache.update-cache, 'updates without problem';

#--MARKER-- Test 12
lives-ok { $cache.freeze }, 'All updated so now can freeze';

rmtree DOC;
#--MARKER-- Test 13
lives-ok { $cache .=new(:path( REP )) }, 'Gets a frozen cache without source';

#--MARKER-- Test 14
throws-like { $cache.update-cache }, Exception, :message(/ 'Cannot update frozen cache'/), 'No updating on a frozen cache';

#--MARKER-- Test 15
throws-like {$cache.pod('xxxyyyzz') }, Exception, :message(/ 'Filename <' \w+ '> not in cache'/), 'Cannot get POD for invalid filename';
