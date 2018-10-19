#!/usr/bin/env perl6
use v6.c;
use lib 'lib';
use Test;
use File::Directory::Tree;

if 't/tmp'.IO ~~ :d  {
    empty-directory 't/tmp';
}
else {
    mktree 't/tmp'
}

use-ok 'Pod::Cached::Render';
use Pod::Cached::Render;
my Pod::Cached::Render $renderer;

throws-like { $renderer .=new(:path<t/tmp/ref>) }, Exception, :message(/'No files in cache'/), 'cache is empty';
