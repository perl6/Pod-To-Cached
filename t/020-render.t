#!/usr/bin/env perl6
use v6.c;
use lib 'lib';
use Test;
use File::Directory::Tree;
use JSON::Fast;

if 't/tmp'.IO ~~ :d  {
    empty-directory 't/tmp';
}
else {
    mktree 't/tmp'
}

use-ok 'Pod::Render';
use Pod::Render;
my Pod::Render $renderer;

throws-like { $renderer .=new(:path<t/tmp/ref>) },
    Exception, :message(/'is not a directory'/), 'cache does not exist';
mktree 't/tmp/ref';
throws-like { $renderer .=new(:path<t/tmp/ref>) },
    Exception, :message(/'No file index in pod cache'/), 'cache does not have file index';
't/tmp/ref/file-index.json'.IO.spurt: ' ';
throws-like { $renderer .=new(:path<t/tmp/ref>) },
    Exception, :message(/'No file index in pod cache'/), 'No files in cache';

done-testing;
