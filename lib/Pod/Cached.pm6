unit class Pod::Cached;

use MONKEY-SEE-NO-EVAL;
use File::Directory::Tree;
use nqp;
use JSON::Fast;

=begin pod

=TITLE Pod::Cached

=SUBTITLE Create a precompiled cache of POD files

Module to take a collection of POD files and create a precompiled cache. Methods / functions
to add a POD file to a cache.

=begin SYNOPSIS
use Pod::Cached;

my Pod::Cached $cache .= new(:path<path-to-cache>, :source<path-to-directory-with-pod-files>);

$cache.update-cache;

for $cache.files -> $filename, %info {
    given %info<status> {
        when 'OK' {say "$filename has valid cached POD"}
        when 'Updated' {say "$filename has valid POD, just updated"}
        when 'Tainted' {say "$filename has been modified since the cache was last updated"}
        when 'Failed' {say "$filename has been modified, but contains invalid POD"}
        when 'Absent' {say "$filename is not in pod-cache"}
    }
    some-routine-for-processing pod( $cache.pod( $filename ) );
}

# Remove the dependence on the pod source
# This means that the pod-cache can be copied without the original pod-files.
# update will generate an error with verbose
$cache.freeze;

# Find files with compile errors
say 'These pod files have errors:';
for $cache.errors.kv -> $fn, $err { say "$fn has error <$err>"}

# List Tainted files
.say for $cache.tainted-files;

# For completeness
$cache.unfreeze;

=end SYNOPSIS

=item Str $!path = 'pod-cache'
    path to the directory where the cache will be created/kept

=item Str $!source = 'doc'
    path to the collection of pod files
    ignored if cache frozen

=item @!extensions = <pod pod6>
    the possible extensions for a POD file

=item verbose = True
    Whether processing information is sent to stderr.

=item new
    Instantiates class. On instantiation, the module verifies that
        - the source directory exists
        - the source directory contains POD/POD6 etc files (recursively)
        - no duplicate filenames exist
        - the status (OK/Tainted) of the cache

=item update-cache
    All files with Status Tainted are precompiled and added to the cache
        - Status is changed to Updated (compiles OK) or Fail (does not compile)

=item files
    public attribute
    a hash of filenames with keys
        -C<status> One of 'OK', 'Tainted', 'Updated', 'Failed', 'Absent'
        - C<cache-key> the key needed to access the compunit cache
        - C<handle> the cache handle
        - C<path> the path to the POD file, not set if cache frozen

=item pod
    method pod(Str $filename, :$when-tainted='none', :$when-absent='note-exit', :when-failed = 'note')
    Returns the POD Object Module generated from the file with the filename.
    The behaviour of pod can be changed for 'tainted', 'absent' and 'failed'.
    'note' issues an error on stderr
    'exit' stops the program at that point
    'none' ignores the pod-name silently

=end pod
constant INDEX = 'file-index.json';

has Str $.path = 'pod-cache';
has Str $.source = 'doc';
has @.extensions = <pod pod6>;
has Bool $.verbose is rw;
has $.precomp;
has $.precomp-store;
has %.files;
has @!pods;
has Bool $.cache-verified = False;
has Bool $.frozen = False;

submethod BUILD( :$!source = 'doc', :$!path = 'pod-cache', :$!verbose = True) {
#    my $threads = %*ENV<THREADS>.?Int // 1;
#    PROCESS::<$SCHEDULER> = ThreadPoolScheduler.new(initial_threads => 0, max_threads => $threads);
    self.get-cache;
    self.verify-cache;
}

method get-cache {
    if $!path.IO ~~ :d {
        # cache path exists, so assume it should contain a cache
        die '$!path appears to have corrupt cache' unless ("$!path/"~INDEX).IO ~~ :f;
        my %config;
        try {
            %config = from-json(("$!path/"~INDEX).slurp);
            CATCH {
                default {
                    die "Configuration failed with: " ~ .message;
                }
            }
        }
        $!frozen = %config<status>;
        %!files = %config<files>;
        $!source = %config<source> unless $!frozen;
        self.verify-source;
    }
    else {
        # check that a source exists before creating a cache
        $!frozen = False;
        self.verify-source;
        mktree $!path;
        self.save-index;
    }
    $!precomp-store = CompUnit::PrecompilationStore::File.new(prefix => $!path.IO );
    $!precomp = CompUnit::PrecompilationRepository::Default.new(store => $!precomp-store);
}

method verify-source {
    return if $!frozen;
    die "$!source is not a directory" unless $!source.IO ~~ :d;
    die "No POD files found under $!source" unless +self.get-pods > 0;
    for @!pods -> $pfile {
        my $nm = $!source eq "." ?? $pfile !! $pfile.substr($!source.chars + 1); # name from source root directory
        $nm = $nm.subst(/ \. \w+ $/, ''); #remove any extension
        die "$nm already exists but with a different extension" if %!files{$nm}:exists;
        %!files{$nm} = (:cache-key(nqp::sha1($nm)), :path($pfile.IO)).hash;
    }
    =comment out
        for pod files that remain unchanged in name, the %!files entry will be changed
        for pod files that change their name, the cache will continue to contain old content
        TODO check whether any files in index are not in doc-set, and remove from cache

}

method verify-cache {
    for %!files.kv -> $pod-name, %info {
        my $handle;
        if $!frozen {
            $handle = $!precomp.load(%info<cache-key>)[0];
        }
        else {
            $handle = $!precomp.load(%info<cache-key>, :since(%info<path>.modified))[0];
        }
        with $handle {
            %!files{$pod-name}<status handle> = 'OK', $handle ;
        }
        else {
            %!files{$pod-name}<status> = $!frozen ?? 'Absent' !! 'Tainted' ;
        }
    }
    note 'Cache verified' if $!verbose;
    $!cache-verified = True;
}

method update-cache {
    if $!frozen {
        note 'Cannot update frozen cache' if $!verbose;
        return
    }
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
            %!files{$pod-name}<status> = 'Updated', $handle ;
        }
        else {
            %!files{$pod-name}<status> = 'Failed';
            note "$pod-name failed to compile" if $!verbose;
        }
    }
    self.save-index
}

method save-index {
    my %h = :frozen( $!frozen ), :files( (
        gather for %!files.kv -> $fn, %inf {
            take $fn => (
                :cache-key( %inf<cache-key>),
                :status( %inf<status>)
                ).hash
        } ).hash );
    %h<source> = $!source unless $!frozen;
    ("$!path/"~INDEX).IO.spurt: to-json(%h);
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

method pod( Str $filename,
                    :$behaviour-failed = 'note',
                    :$behaviour-tainted = 'none',
                    :$behaviour-absent = 'note-exit'
                     ) {
    die 'Cannot provide POD without updated or valid repository'
        unless $!cache-verified;
    sub act-on(Str:D $filename, $behaviour, $message --> Bool) {
        my Bool $rv;
        given $behaviour {
            when m/'note'/ {
                note "$filename: $message";
                $rv = False; # unless 'note exit' given response required
                proceed
            }
            when m/'none'/ { $rv = True } # No response required
            when m/'exit'/ { $rv = True } # exit from module
            default {
                note "$filename: $message";
                $rv = True
            } # like note-exit
        }
        $rv
    }

    given %!files{$filename}<status> {
        when 'Failed' {
            return if act-on($filename, $behaviour-failed,
                'failed to compile with error: ' ~ %!files<error>)
        }
        when 'Tainted' {
            return if act-on($filename, $behaviour-tainted,
                'source pod has been modified')
        }
        when 'Absent' { # this one is generated in verify-cache
            return if act-on($filename, $behaviour-absent,
                'not in document cache')
        }
    }
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
