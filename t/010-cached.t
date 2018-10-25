#!/usr/bin/env perl6
use lib 'lib';
use Test;
use Test::Output;
use File::Directory::Tree;
use JSON::Fast;

constant INDEX = 'file-index.json';

#--MARKER-- Test 1
use-ok 'Pod::Cached';

use Pod::Cached;

if 't/tmp'.IO ~~ :d  {
    empty-directory 't/tmp';
}
else {
    mktree 't/tmp'
}

my Pod::Cached $cache;

mktree 't/tmp/ref';

#--MARKER-- Test 2
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>) },
    Exception, :message(/'has corrupt doc-cache'/), 'Detects absence of index file';

('t/tmp/ref/' ~ INDEX).IO.spurt(q:to/CONTENT/);
    {
        "frozen": "True",
        files: { "one": "ONE", "two": "TWO" }
    }
CONTENT

#--MARKER-- Test 3
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>) },
    Exception, :message(/'Configuration failed'/), 'Bad JSON in index file';

('t/tmp/ref/' ~ INDEX).IO.spurt(q:to/CONTENT/);
        {
            "frozen": "True",
            "files": [ "one", "ONE", "two", "TWO" ],
            "source": "SOURCE"
        }
    CONTENT
#--MARKER-- Test 4
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>) },
    Exception, :message(/'Invalid index file'/), 'Files not hash';

('t/tmp/ref/' ~ INDEX).IO.spurt(q:to/CONTENT/);
        {
            "files": { "one": "ONE", "two": "TWO" },
            "source": "SOURCE"
        }
    CONTENT
#--MARKER-- Test 5
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>) },
    Exception, :message(/'Invalid index file'/), 'No frozen';

('t/tmp/ref/' ~ INDEX).IO.spurt(q:to/CONTENT/);
        {
            "frozen": "True",
            "source": "SOURCE"
        }
    CONTENT
#--MARKER-- Test 6
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>) },
    Exception, :message(/'Invalid index file'/), 'No files';

('t/tmp/ref/' ~ INDEX).IO.spurt(q:to/CONTENT/);
        {
            "frozen": "False",
            "files": { "one": "ONE", "two": "TWO" }
        }
    CONTENT
#--MARKER-- Test 7
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>) },
    Exception, :message(/'Invalid index file'/), 'No source without frozen';

('t/tmp/ref/' ~ INDEX).IO.spurt(q:to/CONTENT/);
        {
            "frozen": "False",
            "files": { "one": "ONE", "two": "TWO" },
            "source": "t/tmp/doc"
        }
    CONTENT
#--MARKER-- Test 8
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>) },
    Exception, :message(/'Source verification failed'/), 'No source directory at source in index';

# TODO source-verify with frozen cache
rmtree 't/tmp/ref';

#--MARKER-- Test 9
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>) },
    Exception, :message(/'is not a directory'/), 'Detects absence of source directory';

mktree 't/tmp/doc';
#--MARKER-- Test 10
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>)},
    Exception, :message(/'No POD files found under'/), 'Detects absence of source files';

't/tmp/doc/a-pod-file.pod6'.IO.spurt(q:to/POD-CONTENT/);
    =pod A test file
    =TITLE This is a title

    Some text

    =end pod
    POD-CONTENT

't/tmp/doc/a-second-pod-file.pod6'.IO.spurt(q:to/POD-CONTENT/);
    =pod Another test file
    =TITLE More and more

    Some more text

    =end pod
    POD-CONTENT
#| Change the extension but not the name
't/tmp/doc/a-second-pod-file.pod'.IO.spurt(q:to/POD-CONTENT/);
    =pod Another test file
    =TITLE More and more

    Some more text

    =end pod
    POD-CONTENT

#--MARKER-- Test 11
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>)},
    Exception, :message(/'More than one POD file named'/), 'Detects duplication of source file names';

't/tmp/doc/a-second-pod-file.pod'.IO.unlink ;
#--MARKER-- Test 12
nok 't/tmp/ref'.IO ~~ :d, 'No cache directory should be created yet';
#--MARKER-- Test 13
lives-ok { $cache = Pod::Cached.new(:source<t/tmp/doc>, :path<t/tmp/ref>, :!verbose) }, 'Instantiates OK';
#--MARKER-- Test 14
ok 't/tmp/ref'.IO ~~ :d, 'Correctly creates the cache directory';
#--MARKER-- Test 15
ok ('t/tmp/ref/' ~ INDEX).IO ~~ :f, 'index file has been created';
my %config;
#--MARKER-- Test 16
lives-ok { %config = from-json( ('t/tmp/ref/' ~ INDEX).IO.slurp ) }, 'good json in index';
#--MARKER-- Test 17
ok (%config<frozen>:exists and %config<frozen> ~~ 'False'), 'frozen as expected';
#--MARKER-- Test 18
ok (%config<files>:exists
    and %config<files>.WHAT ~~ Hash)
    , 'files is as expected';
#--MARKER-- Test 19
is +%config<files>.keys, 2, 'Two pod files in index';

#--MARKER-- Test 20
is +$cache.list-files( Pod::Cached::New ),  2, 'Both pod files are marked as New to cache';
#--MARKER-- Test 21
is +gather for %config<files>.kv -> $pname, %info {
    take $pname if %info<status> ~~ Pod::Cached::New.Str
}, 2, 'Index matches object about files';

my $mod-time = ('t/tmp/ref/' ~ INDEX).IO.modified;
my $rv;
#--MARKER-- Test 22
lives-ok {$rv = $cache.update-cache}, 'Updates cache without dying';
#--MARKER-- Test 23
nok $rv, 'Returned false because of compile errors';
#--MARKER-- Test 24
like $cache.error-messages[0], /'Compile error in'/, 'Error messages saved';
#--MARKER-- Test 25
nok ('t/tmp/ref/' ~ INDEX).IO.modified > $mod-time, 'INDEX not modified';
#--MARKER-- Test 26
is +$cache.list-files( Pod::Cached::Failed ), 2, 'Both pod files contain errors';
#--MARKER-- Test 27
is +gather for $cache.files.kv -> $nm, %inf { take 'f' unless %inf<handle>:exists },
    2, 'No handles are defined for New & Failed files';

$cache.verbose = True;
#--MARKER-- Test 28
stderr-like { $cache.update-cache }, /'Cache not fully updated'/, 'Got correct progress message';
$cache.verbose = False;
't/tmp/doc/a-pod-file.pod6'.IO.spurt(q:to/POD-CONTENT/);
    =begin pod
    =TITLE This is a title

    Some text

    =end pod
    POD-CONTENT

't/tmp/doc/a-second-pod-file.pod6'.IO.spurt(q:to/POD-CONTENT/);
    =begin pod
    =TITLE More and more

    Some more text

    =end pod
    POD-CONTENT

#--MARKER-- Test 29
ok $cache.update-cache, 'Returned true because both POD now compile';

#--MARKER-- Test 30
is +$cache.list-files( Pod::Cached::Updated ), 2, 'Two files have been modified';

#--MARKER-- Test 31
ok ('t/tmp/ref/' ~ INDEX).IO.modified > $mod-time, 'INDEX has been modified';

#--MARKER-- Test 32
ok $cache.pod('a-pod-file') ~~ Pod::Block::Named, 'pod is returned from cache';

't/tmp/doc/a-second-pod-file.pod6'.IO.spurt(q:to/POD-CONTENT/);
    =begin pod
    =TITLE More and more

    Some more text but now it is changed

    =end pod
    POD-CONTENT
%config = from-json(('t/tmp/ref/' ~ INDEX).IO.slurp);
dd %config;
#--MARKER-- Test 33
lives-ok {$cache .=new(:path<t/tmp/ref>, :verbose)}, 'with a valid cache, source can be omitted';
dd $cache.list-files( :all );
#--MARKER-- Test 34
is +$cache.list-files( Pod::Cached::Tainted ), 1, 'A pod file identified as needing updating';
#--MARKER-- Test 35
is +$cache.list-files( :all ).keys, 2, 'One Updated, one Valid';
#--MARKER-- Test 36
is +$cache.list-files( Pod::Cached::Valid ), 1, 'Yep, valid';

=begin out
#--MARKER-- Test 37
throws-like { $cache.pod('a-second-pod-file', :when-tainted('exit')) }, Exception,
    :message(/ 'POD called with exit processing'/), 'Pod should fail if tainted behaviour exit';
#--MARKER-- Test 38
is $cache.pod('a-second-pod-file', :when-tainted('none')), Nil, 'Nil return for none';
#--MARKER-- Test 39
stderr-like { $rv = $cache.pod('a-second-pod-file', :when-tainted('note')) }, /'source pod has been modified'/, 'An error message when note';
#--MARKER-- Test 40
is $rv, Pod::Block::Named, 'pod supplies output for note because previous version still in cache';
#--MARKER-- Test 41
stderr-like {$rv = $cache.pod('a-second-pod-file', :when-tainted('note-none'))}, /'source pod has been modified'/, 'Same error message when note-none';
#--MARKER-- Test 42
is $rv, Nil, 'produces a note, but no POD';

diag 'testing freeze';
#--MARKER-- Test 43
throws-like { $cache.freeze }, Exception, :message(/'Cannot freeze because the following'/), 'Cant freeze when a file is tainted';

#--MARKER-- Test 44
ok $cache.update-cache, 'updates without problem';

#--MARKER-- Test 45
lives-ok { $cache.freeze }, 'All updated so now can freeze';

rmtree 't/tmp/doc';
#--MARKER-- Test 46
lives-ok { $cache .=new('t/tmp/ref') }, 'Gets a frozen cache without source';

#--MARKER-- Test 47
throws-like { $cache.update-cache }, Exception, :message(/ 'Cannot update frozen cache'/), 'No updating on a frozen cache';

#--MARKER-- Test 48
throws-like {$cache.pod('xxxyyyzz') }, Exception, :message(/ 'Cannot provide POD without valid cache'/), 'Cannot get POD for invalid filename';
=end out
done-testing;
