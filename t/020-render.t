#!/usr/bin/env perl6
use v6.c;
use lib 'lib';
use Test;
use File::Directory::Tree;
use JSON::Fast;
done-testing;
if 't/tmp'.IO ~~ :d  {
    empty-directory 't/tmp';
}
else {
    mktree 't/tmp'
}

#--MARKER-- Test 1
use-ok 'Pod::Render';
use Pod::Render;
my Pod::Render $renderer;

#--MARKER-- Test 2
throws-like { $renderer .=new(:path<t/tmp/ref>) },
    Exception, :message(/'is not a directory'/), 'cache does not exist';
mktree 't/tmp/ref';
#--MARKER-- Test 3
throws-like { $renderer .=new(:path<t/tmp/ref>) },
    Exception, :message(/'No file index in pod cache'/), 'cache does not have file index';
't/tmp/ref/file-index.json'.IO.spurt: ' ';
#--MARKER-- Test 4
throws-like { $renderer .=new(:path<t/tmp/ref>) },
    Exception, :message(/'No file index in pod cache'/), 'No files in cache';

done-testing;
