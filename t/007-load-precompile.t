use v6.c;

use Test;
use nqp;
use CompUnit::PrecompilationRepository::Document;
use File::Directory::Tree;

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
    # that regex matchs a sha1 name
    my @dirs = dir( "cache/", test => /<[A..Z 0..9]> ** 5..40/);
    is @dirs.elems, 1, "Cached dir created";
    my $dir = @dirs[0] ~ "/" ~ $key.substr(0,2);
    ok $dir.IO.d, "Key directory created";
    ok "$dir/$key".IO.f, "File cached";
}

rmtree(cache-name);

done-testing;

=begin pod

=TITLE Powerful cache

Raku is quite awesome.

=end pod
