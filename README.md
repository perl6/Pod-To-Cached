# Pod::To::Cached

[![Build Status](https://travis-ci.com/perl6/Pod-To-Cached.svg?branch=master)](https://travis-ci.com/perl6/Pod-To-Cached)
[![Appveyor Build Status](https://ci.appveyor.com/api/projects/status/github/perl6/Pod-To-Cached?svg=true)](https://ci.appveyor.com/api/projects/status/github/perl6/Pod-To-Cached?svg=true)

Create and Maintain a cache of precompiled pod files

Module to take a collection of pod files and create a precompiled cache. Methods / functions
to add a pod file to a cache.

## Install

This module is in the [Raku ecosystem](https://modules.raku.org), so you
 install it in the usual way:

    zef install Pod::To::Cached

Although this module is usable, it will be soon substituted by [`Pod::From::Cached`](https://github.com/finanalyst/raku-pod-from-cache). So it's
 probably better if you try and adapt to that new module.

The module is now in maintenance mode, and only bugfixes will be released.

# SYNOPSIS
```perl6
use Pod::To::Cached;

my Pod::To::Cached $cache .= new(:path<path-to-cache>, :source<path-to-directory-with-pod-files>);

$cache.update-cache;

for $cache.hash-files.kv -> $source-name, $status {
    given $status {
        when 'Current' {say "｢$source-name｣ is up to date with POD source"}
        when 'Valid' {say "｢$source-name｣ has valid POD, but newer POD source contains invalid POD"}
        when 'Failed' {say "｢$source-name｣ is not in cache, and source file contains invalid POD"}
        when 'New' { say "｢$source-name｣ is not in cache and cache has not been updated"}
        when 'Old' { say "｢$source-name｣ is in cache, but has no associated pod file in DOC"}
    }
    user-supplied-routine-for-processing-pod( $cache.pod( $source-name ) );
}

# Find files with status
say 'These pod files failed:';
.say for $cache.list-files( 'Failed' );
say 'These sources have valid pod:';
.say for $cache.list-files(<Current Valid>);

# Find date when pod added to cache
my $source = 'language/pod'; # name of a documentation source
say "｢$source｣ was added on ｢{ $cache.cache-timestamp( $source ) }｣";

# Remove the dependence on the pod source
$cache.freeze;

```
## Notes
-  Str $!path = '.pod6-cache'  
    path to the directory where the cache will be created/kept

-  Str $!source = 'doc'  
    path to the collection of pod files
    ignored if cache frozen

-  @!extensions = <pod pod6>  
    the possible extensions for a POD file

-  verbose = False  
    Whether processing information is sent to stderr.

-  new  
    Instantiates class. On instantiation,
    - get the cache from index, or creates a new cache if one does not exist
    - if frozen, does not check the source directory
    - if not frozen, or new cache being created, verifies
        - source directory exists
        - the source directory contains POD/POD6 etc files (recursively)
        - no duplicate pod file names exist, eg. xx.pod & xx.pod6
    - verifies whether the cache is valid

-  update-cache  
    All files with a modified timestamp (reported by the filesystem) after the added instant are precompiled and added to the cache
    - Status is changed to Updated (compiles Valid) or Fail (does not compile)
    - Failed files that were previously Valid files still retain the old cache handle
    - Throws an exception when called on a frozen cache

-  freeze  
    Can be called only when there are only Valid or Updated (no New, Tainted or Failed files),
    otherwise dies.  
    The intent of this method is to allow the pod-cache to be copied without the original pod-files.  
    update-cache will throw an error if used on a frozen cache

-  list-files( Str $s --> Positional )
    returns an Sequence of files with the given status

-  list-files( Str $s1, $s2 --> Positional )
    returns an Array of files with the given status list

-  hash-files( *@statuses? --> Associative )
    returns a map of the source-name and its statuses
    -  explicitly give required status strings: C<< $cache.hash-files(<Old Failed>) >>
    -  return all files C< $cache.hash-files >

-  cache-timestamp( $source --> Instant )
    returns the Instant when a valid version of the Pod was added to the cache
    -  if the time-stamp is before the time the Pod was modified, then the pod has errors
    -  a Failed source has a timestamp of zero

-  pod
    - method pod(Str $source)
    - Returns an array of POD Objects generated from the file associated with $source name.
    - When a doc-set is being actively updated, then pod files may have failed, in which case they have Status Valid.
    - To froze a cache, all files must have Current status

-  Status is an enum with the following elements and semantics
    -  Current  
         There is a compiled source in the cache with an added date **after** the modified date
    -  Valid  
    There is a compiled source in the cache with an added date **before** the modified date and there has been an attempt to add the source to cache that did not compile
    -  Failed  
    There is not a compiled source in the cache, but there has been an attempt to add the source name to the cache that did not compile
    -  New  
    A new pod source has been detected that is not in cache, but C<update-cache> has not yet been called to compile the source. A transitional Status
    -  Old  
    A source name that is in the cache but no longer reflects an existing source.

## LICENSE

You can use and distribute this module under the terms of the The Artistic License 2.0. See the LICENSE file included in this distribution for complete details.

The META6.json file of this distribution may be distributed and modified without restrictions or attribution.
