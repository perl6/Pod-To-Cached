unit class Pod::Cached;

use MONKEY-SEE-NO-EVAL;
use File::Directory::Tree;
use nqp;

=begin pod

=TITLE Pod::Cached

=SUBTITLE Create a precompiled cache of pod files

Module to take a collection of pod files and create a precompiled cache. Methods / functions
to add a pod file to a cache.

=begin SYNOPSIS
use Pod::Cached;

my Pod::Cached $cache .= new(:path<path-to-cache>, :source<path-to-directory-with-pod-files>);

$cache.update-cache;

for $cache.files -> $filename, %info {
    given %info<status> {
        when 'OK' {say "$filename has valid cached pod"}
        when 'Updated' {say "$filename has valid pod, just updated"}
        when 'Tainted' {say "$filename has been modified since the cache was last updated"}
        when 'Failed' {say "$filename has been modified, but contains invalid pod"}
    }
    some-routine-for-processing pod( $cache.pod( $filename ) );
}


=end SYNOPSIS

=item Str $!path = 'pod-cache'
    path to the directory where the cache will be created/kept

=item Str $!source = 'doc'
    path to the collection of pod files

=item @!extensions = <pod pod6>
    the possible extensions for a pod file

=item verbose = True
    Whether processing information is sent to stderr.

=item new
    Instantiates class. On instantiation, the module verifies that
        - the source directory exists
        - the source directory contains pod/pod6 etc files (recursively)
        - no duplicate filenames exist
        - the status (OK/Tainted) of the cache

=item update-cache
    All files with Status Tainted are precompiled and added to the cache
        - Status is changed to Updated (compiles OK) or Fail (does not compile)

=item files
    public attribute
    a hash of filenames with keys
        -C<status> One of 'OK', 'Tainted', 'Updated', 'Failed'
        - C<cache-key> the key needed to access the compunit cache
        - C<handle> the cache handle
        - C<path> the path to the pod file

=item pod
    method pod(Str $filename:D )
    Returns the Pod Object Module generated from the file with the filename.

=end pod

has Str $!path = 'pod-cache';
has Str $!source = 'doc';
has @!extensions = <pod pod6>;
has Bool $.verbose is rw;
has $!precomp;
has $!precomp-store;
has %.files;
has @!pods;

submethod BUILD( :$!source, :$!path, :$!verbose = True) {
    self.verify-source;
    self.verify-cache;
}

method verify-source {
    die "$!source is not a directory" unless $!source.IO ~~ :d;
    die "No pod files found under $!source" unless +self.get-pods > 0;
    for @!pods -> $pfile {
        my $nm = $!source eq "." ?? $pfile !! $pfile.substr($!source.chars + 1); # name from source root directory
        $nm = $nm.subst(/ \. \w+ $/, ''); #remove any extension
        die "$nm already exists but with a different extension" if %!files{$nm}:exists;
        %!files{$nm} = (:cache-key(nqp::sha1($nm)), :path($pfile.IO)).hash;
    }
}

method verify-cache {
    mktree $!path unless $!path.IO ~~ :d;
    my $threads = %*ENV<THREADS>.?Int // 1;
    PROCESS::<$SCHEDULER> = ThreadPoolScheduler.new(initial_threads => 0, max_threads => $threads);
    $!precomp-store = CompUnit::PrecompilationStore::File.new(prefix => $!path.IO );
    $!precomp = CompUnit::PrecompilationRepository::Default.new(store => $!precomp-store);
    for %!files.kv -> $pod-name, %info {
        my $handle = $!precomp.load(%info<cache-key>, :since(%info<path>.modified))[0];
        with $handle {
            %!files{$pod-name}<status handle> = 'OK', $handle ;
        }
        else {
            %!files{$pod-name}<status> = 'Tainted';
        }
    }
    note 'Cache verified' if $!verbose;
}

method update-cache {
    for %!files.kv -> $pod-name, %info {
        next if %info<status> ~~ <OK Updated>;
        note "Processing $pod-name" if $!verbose;
        my $handle;
        try {
            $!precomp.precompile(%info<path>, %info<cache-key>, :force);
            $handle = $!precomp.load(%info<cache-key>)[0];
            CATCH {
                default {
                    %!files{$pod-name}<error> = .Str;
                }
            }
        }
        with $handle {
            %!files{$pod-name}<status handle> = 'Updated', $handle ;
        }
        else {
            %!files{$pod-name}<status> = 'Failed';
            note "$pod-name failed to compile" if $!verbose;
        }
    }
}

method get-pods {
    return @!pods if +@!pods;
    #| Recursively finds all pod files
     my $all-extensions = @!extensions.join("|");
     my $ending-rx = rx:i/ <$all-extensions> $ /;
     @!pods = my sub recurse ($dir) {
         gather for dir($dir) {
             take .Str if  .extension ~~ $ending-rx;
             take slip sort recurse $_ if .d;
         }
     }($!source)
}

method pod( Str $filename ) {
    return (note "$filename status is " ~ %!files{$filename}<status>) if %!files{$filename}<status> ~~ <Failed Tainted>;
    nqp::atkey(%!files{$filename}<handle>.unit,'$=pod')[0];
}

method failures {
    gather for %!files.kv -> $pname, %info {
        next unless %info<status> eq 'Failed';
        take $pname => (%info<error> // 'no error given');
    }.hash
}

method tainted-files {
    gather for %!files.kv -> $pname, %info {
        take $pname if %info<status> eq 'Tainted'
    }
}
