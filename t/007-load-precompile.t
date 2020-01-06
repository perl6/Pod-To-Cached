use v6.c;

use Test;
use nqp;
use CompUnit::PrecompilationRepository::Document;
use File::Directory::Tree;

plan 2;

constant cache-name = "cache";
my $precomp-store = CompUnit::PrecompilationStore::File.new(prefix =>
        cache-name.IO );
my $precomp = CompUnit::PrecompilationRepository::Document.new(store => $precomp-store);

for <simple sub/simple> -> $doc-name {
    my $key = nqp::sha1($doc-name);
    $precomp.precompile("t/doctest/$doc-name.pod6".IO, $key, :force );
    my $handle = $precomp.load($key)[0];
    my $precompiled-pod = nqp::atkey($handle.unit,'$=pod')[0];
    is-deeply $precompiled-pod, $=pod[0], "Load precompiled pod $doc-name";
}

rmtree(cache-name);

=begin pod

=TITLE Powerful cache

Raku is quite awesome.

=end pod
