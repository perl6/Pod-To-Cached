#!/usr/bin/env perl6
use lib 'lib';
use Test;
use Test::Output;
use File::Directory::Tree;

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
    Exception, :message(/'appears to have corrupt cache'/), 'Detects absence of index file';

rmtree 't/tmp/ref';

$cache = Nil;
#--MARKER-- Test 3
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>) },
    Exception, :message(/'is not a directory'/), 'Detects absence of source directory';

$cache = Nil;
mktree 't/tmp/doc';
#--MARKER-- Test 4
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>)},
    Exception, :message(/'No POD files found under'/), 'Detects absence of source files';

$cache = Nil;
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

#--MARKER-- Test 5
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>)},
    Exception, :message(/'already exists but with a different extension'/), 'Detects duplication of source file names';

't/tmp/doc/a-second-pod-file.pod'.IO.unlink ;

#--MARKER-- Test 6
lives-ok { $cache = Pod::Cached.new(:source<t/tmp/doc>, :path<t/tmp/ref>, :!verbose) }, 'Instantiates OK';
#--MARKER-- Test 7
ok 't/tmp/ref'.IO ~~ :d, 'Correctly creates the repo directory';
#--MARKER-- Test 8
ok 't/tmp/ref/file-index.json'.IO ~~ :f, 'index file has been created';

#--MARKER-- Test 9
lives-ok {$cache.verify-cache}, 'Verifies cache without dying';

#--MARKER-- Test 10
is +$cache.tainted-files,  2, 'Neither of the pod files are in the cache';

#--MARKER-- Test 11
lives-ok {$cache.update-cache}, 'Updates cache without dying';

#--MARKER-- Test 12
is +$cache.failures.keys, 2, 'Both pod files contain errors';

$cache = Nil;
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

# turn on verbose
#--MARKER-- Test 13
=begin out

stderr-like {$cache = Pod::Cached.new(:source<t/tmp/doc>, :path<t/tmp/ref>, :verbose ) },
    /'Cache verified'/, 'verbose flag generates output on stderr';
$cache.verbose = False;

#--MARKER-- Test 14
ok +$cache.tainted-files == 2, 'Found two files have been modified';

$cache.update-cache;
#--MARKER-- Test 15
nok +$cache.failures.keys, 'Both pod files are correct';

#--MARKER-- Test 16
ok $cache.pod('a-pod-file') ~~ Pod::Block::Named, 'pod is returned from cache';

=end out

done-testing;
