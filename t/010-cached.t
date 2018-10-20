#!/usr/bin/env perl6
use lib 'lib';
use Test;
use Test::Output;
use File::Directory::Tree;

use-ok 'Pod::Cached';

use Pod::Cached;
if 't/tmp'.IO ~~ :d  {
    empty-directory 't/tmp';
}
else {
    mktree 't/tmp'
}

my Pod::Cached $cache;
throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>) },
    Exception, :message(/'is not a directory'/), 'Detects absence of source directory';

$cache = Nil;
mktree 't/tmp/doc';
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

throws-like { $cache .= new(:source<t/tmp/doc>, :path<t/tmp/ref>)},
    Exception, :message(/'already exists but with a different extension'/), 'Detects duplication of source file names';

't/tmp/doc/a-second-pod-file.pod'.IO.unlink ;

lives-ok { $cache = Pod::Cached.new(:source<t/tmp/doc>, :path<t/tmp/ref>, :!verbose) }, 'Instantiates OK';
ok 't/tmp/ref'.IO ~~ :d, 'Correctly creates the repo directory';

lives-ok {$cache.update-cache}, 'Verifies cache without dying';

ok +$cache.failures.keys == 2, 'Both pod files contain errors';

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
stderr-like {$cache = Pod::Cached.new(:source<t/tmp/doc>, :path<t/tmp/ref>, :verbose ) },
    /'Cache verified'/, 'verbose flag generates output on stderr';
$cache.verbose = False;

ok +$cache.tainted-files == 2, 'Found two files have been modified';

$cache.update-cache;
nok +$cache.failures.keys, 'Both pod files are correct';
ok 't/tmp/ref/file-index.json'.IO ~~ :f, 'index file has been created';

ok $cache.pod('a-pod-file') ~~ Pod::Block::Named, 'pod is returned from cache';

done-testing;
