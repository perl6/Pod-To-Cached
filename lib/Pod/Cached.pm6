unit class Pod::Cached;

=begin pod

=TITLE Pod::Cached

=SUBTITLE Create a precompiled cache of pod files

Module to take a collection of pod files and create a precompiled cache. Methods / functions
to add a pod file to a cache.

=begin SYNOPSIS



=end SYNOPSIS

=end pod

constant NL = "\n";

my &verbose = &note;


#| Sets verbose value
sub set-verbose(&new-verbose) is export {
    &verbose = &new-verbose
}
