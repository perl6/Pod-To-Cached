unit class Pod::To::Cached;

use MONKEY-SEE-NO-EVAL;
use File::Directory::Tree;
use nqp;
use JSON::Fast;
use PrecompilationDoc;

=begin pod

=TITLE Pod::To::Cached

=SUBTITLE Create a precompiled cache of POD files

Module to take a collection of POD files and create a precompiled cache. Methods / functions
to add a POD file to a cache.

=begin SYNOPSIS
use Pod::To::Cached;

my Pod::To::Cached $cache .= new(:path<path-to-cache>, :source<path-to-directory-with-pod-files>);

$cache.update-cache;

for $cache.list-files( :all ).kv -> $source-name, $status {
    given $status {
        when 'Current' {say "｢$source-name｣ is up to date with POD source"}
        when 'Valid' {say "｢$source-name｣ has valid POD, but newer POD source contains invalid POD"}
        when 'Failed' {say "｢$source-name｣ is not in cache, and source file contains invalid POD"}
        when 'New' { say "｢$source-name｣ is not in cache and cache has not been updated"}
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

=end SYNOPSIS

=item Str $.path = '.pod6-cache'
    path to the directory where the cache will be created/kept

=item Str $!source = 'doc'
    path to the collection of pod files
    ignored if cache frozen

=item @!extensions = <pod pod6>
    the possible extensions for a POD file

=item verbose = False
    Whether processing information is sent to stderr.

=begin item
    new
    Instantiates class. On instantiation,
=item2 get the cache from index, or creates a new cache if one does not exist
=item2 if frozen, does not check the source directory
=item2 if not frozen, or new cache being created, verifies
=item3  source directory exists
=item3 no duplicate pod file names exist, eg. xx.pod & xx.pod6
=item2 verifies whether the cache is valid
=end item

=item update-cache
    All files with a modified timestamp (reported by the filesystem) after the added instant are precompiled and added to the cache
=item2 Status is changed to Updated (compiles Valid) or Fail (does not compile)
=item2 Failed files that were previously Valid files still retain the old cache handle
=item2 Throws an exception when called on a frozen cache

=item freeze
    Can be called only when there are only Valid or Updated (no New, Tainted or Failed files),
    otherwise dies.
    The intent of this method is to allow the pod-cache to be copied without the original pod-files.
    update-cache will throw an error if used on a frozen cache

=item list-files( Str $s --> Positional )
    returns an Sequence of files with the given status

=item list-files( Str $s1, $s2 --> Array )
    returns an Array of files with the given status list

=item list-files( :all --> Associative )
    returns an Sequence of files with the given status

=item cache-timestamp( $source --> Instant )
    returns the Instant when a valid version of the Pod was added to the cache
=item2 if the time-stamp is before the time the Pod was modified, then the pod has errors
=item2 a Failed source has a timestamp of zero

=item pod
    method pod(Str $source)
    Returns the POD Object generated from the file associated with $source name.
    When a doc-set is being actively updated, then pod files may have failed.
    To froze a cache, all files must have Current status

=item Status is an enum with the following elements and semantics
=defn Current
    There is a compiled source in the cache with an added date *after* the modified date
=defn Valid
    There is a compiled source in the cache with an added date *before* the modified date and there has been an attempt to add the source to cache that did not compile
=defn Failed
    There is not a compiled source in the cache, but there has been an attempt to add the source name to the cache that did not compile
=defn New
    A new pod source has been detected that is not in cache, but C<update-cache> has not yet been called to compile the source. A transitional Status

=end pod

constant INDEX = 'file-index.json';
enum Status  is export <Current Valid Failed New>; # New is internally used, but not stored in DB

has Str $.path = '.pod6-cache';
has Str $.source = 'doc';
has @.extensions = <pod pod6>;
has Bool $.verbose is rw;
has $.precomp;
has $.precomp-store;
has %.files;
has @!pods;
has Bool $.frozen = False;
has Str @.error-messages;

submethod BUILD( :$!source = 'doc', :$!path = '.pod-cache', :$!verbose = False) {
#    my $threads = %*ENV<THREADS>.?Int // 1;
#    PROCESS::<$SCHEDULER> = ThreadPoolScheduler.new(initial_threads => 0, max_threads => $threads);
}

submethod TWEAK {
    self.get-cache;
}

method get-cache {
    if $!path.IO ~~ :d {
        # cache path exists, so assume it should contain a cache
        die '$!path has corrupt doc-cache' unless ("$!path/"~INDEX).IO ~~ :f;
        my %config;
        try {
            %config = from-json(("$!path/"~INDEX).IO.slurp);
            CATCH {
                default {
                    die "Configuration failed with: " ~ .message;
                }
            }
        }
        die "Invalid index file"
            unless
                %config<frozen>:exists
                and %config<files>:exists
                and %config<files>.WHAT ~~ Hash
        ;
        $!frozen = %config<frozen> eq 'True';
        %!files = %config<files>;
        unless $!frozen {
            die "Invalid index file"
                unless %config<source>:exists;
            $!source = %config<source>;
            %!files.map( {
                .value<status> = Status( .value<status> ) ;
                .value<added> = DateTime.new( .value<added> ).Instant
            })
        }
        die "Source verification failed with:\n" ~ @!error-messages.join("\n\t")
            unless self.verify-source; # note a frozen cache always returns True
    }
    else {
        # check that a source exists before creating a cache
        $!frozen = False;
        die "Source verification failed with:\n" ~ @!error-messages.join("\n\t")
            unless self.verify-source;
        mktree $!path;
        self.save-index;
    }
    $!precomp-store = CompUnit::PrecompilationStore::File.new(prefix => $!path.IO );
    $!precomp = CompUnit::PrecompilationRepository::Document.new(store => $!precomp-store);
    # get handles for all Valid / Current files

    for %!files.kv -> $nm, %info {
        next unless %info<status> ~~ any( Valid, Current );
        die "No handle for <$nm> in cache, but marked as existing. Cache corrupted."
            without %!files{$nm}<handle> = $!precomp.load(%info<cache-key>)[0];
    }
    note "Got cache at $!path" if $!verbose;
}

method verify-source( --> Bool ) {
    return True if $!frozen;
    (@!error-messages = "$!source is not a directory", ) and return False
        unless $!source.IO ~~ :d;
    (@!error-messages = "No POD files found under $!source", ) and return False
        unless +self.get-pods > 0;
    my $rv = True;
    for @!pods -> $pfile {
        my $nm = $!source eq "." ?? $pfile !! $pfile.substr($!source.chars + 1); # name from source root directory
        # Normalise the cache name.
        # For some reason, all names & directories made lower case and extension removed.
        $nm = $nm.subst(/ \. \w+ $/, '').lc;
        if %!files{$nm}:exists {
            if %!files{$nm}<path> eq $pfile {
                # detect tainted source
                %!files{$nm}<status> = Valid if %!files{$nm}<added> < %!files{$nm}<path>.IO.modified;
            }
            else {
                @!error-messages.push("$pfile duplicates name of " ~ %!files{$nm}<path> ~ " but with different extension");
                $rv = False ;
            }
        }
        else {
            %!files{$nm} = (:cache-key(nqp::sha1($nm)), :path($pfile), :status( New ), :added(0) ).hash;
        }
    }
    =comment out garbage collection
    my Set $garbage = Set.new( @!pods ) (-) Set.new( %!files.keys) ;
    if $garbage.elems {
        @!error-messages.push("Cache contains the following pod not in source\n" ~ $garbage);
        $rv = False;
    }
     $!precomp-store.remove-from-cache(CompUnit::PrecompilationId $precomp-id)

    =comment ary
        for pod files that remain unchanged in name, the %!files entry will be changed.
        but for pod files that change their name, the cache will continue to contain old content
        TODO cache garbage collection: check whether any files not in index but are in doc-set, and remove from cache

    note 'Source verified' if $!verbose;
    $rv
}

method update-cache( --> Bool ) {
    =comment update-cache may be called repeatedly on a cache

    die 'Cannot update frozen cache' if $!frozen;
    my $rv = True;
    @!error-messages = ();

    for %!files.kv -> $source-name, %info {
        next if %info<status> ~~ Current;
        note "Caching $source-name" if $!verbose;
        my $handle;
        try {
            CATCH {
                default {
                    @!error-messages.push: "Compile error in $source-name:\n\t" ~ .Str;
                    $rv = False;
                }
            }
            $!precomp.precompile(%info<path>.IO, %info<cache-key>, :force );
            $handle = $!precomp.load(%info<cache-key>)[0];
        }
        with $handle {
            %!files{$source-name}<status handle added> = Current , $handle, now ;
        }
        else {
            %!files{$source-name}<status> = Failed if %!files{$source-name}<status> ~~ New ; # those marked Valid remain Valid
            note "$source-name failed to compile" if $!verbose;
            $rv = False; # belt and braces, since this probably should be set in CATCH phaser
            # A new and failed pod will not have a handle
        }
    }
    note( @!error-messages.join("\n")) if $!verbose and +@!error-messages;
    self.save-index if $rv;
    note ('Cache ' ~ ( $rv ?? '' !! 'not ' ) ~ 'fully updated') if $!verbose;
    $rv # we leave the $!cache-verified flag True because what is in the cache is verified
}

method save-index {
    my %h = :frozen( $!frozen ), :files( (
        gather for %!files.kv -> $fn, %inf {
            next if %inf<status> ~~ New; # do not allow New to be saved in index
            if $!frozen {
                take $fn => (
                    :cache-key(%inf<cache-key>),
                    :status( Current ),
                    :added( %inf<added> ),
                ).hash
            }
            else {
                take $fn => (
                    :cache-key(%inf<cache-key>),
                    :status( %inf<status> ),
                    :added( %inf<added> ),
                    :path(%inf<path>),
                ).hash
            }
        } ).hash );
    %h<source> = $!source unless $!frozen;
    ("$!path/"~INDEX).IO.spurt: to-json(%h);
}

method get-pods {
    die 'No pods accessible for a frozen cache' if $!frozen; # should never get here
    return @!pods if +@!pods;
    #| Recursively finds all pod files
     @!pods = my sub recurse ($dir) {
         gather for dir($dir) {
             take .Str if  .extension ~~ any( @!extensions );
             take slip sort recurse $_ if .d;
         }
     }($!source); # is the first definition of $dir
}

method pod( Str $source-name ) is export {
    die "Source name ｢$source-name｣ not in cache" unless $source-name ~~ any(%!files.keys);
    die "Attempt to obtain non-existent POD for <$source-name>. Is the source new and failed to compile? Has the cache been updated?"
        without %!files{$source-name}<handle>;
    nqp::atkey(%!files{$source-name}<handle>.unit,'$=pod')[0];
}

multi method list-files( Str $s --> Positional ) {
    return () unless $s ~~ any(Status.enums.keys);
    gather for %!files.kv -> $pname, %info {
        take $pname if %info<status> ~~ $s
    }.sort.list
}

# The following is ugly, but cleaner ways seem to choke when list-file str returns Nil

multi method list-files( *@statuses --> Positional ) {
    my @s;
    for @statuses {
        my @a = self.list-files( $_ );
        @s.append(  |@a ) if +@a
    }
    @s.sort.list
}

multi method list-files( Bool :$all --> Hash) {
    return %( ) unless $all;
    ( gather for %.files.kv -> $pname, %info {
        take $pname => %info<status>.Str
    }).hash
}

method cache-timestamp( $source --> Instant ) {
    %.files{ $source }<added>
}

method freeze( --> Bool ) {
    return if $!frozen;
    my @not-ok = gather for %!files.kv -> $pname, %info {
        take $pname unless %info<status> ~~ Current
    }
    die "Cannot freeze because the following are either Valid (source file is newer than cached object) or Failed (source not added to cache):\n" ~ @not-ok.join("\n\t")
        if +@not-ok;
    $!frozen = True;
    self.save-index;
}
