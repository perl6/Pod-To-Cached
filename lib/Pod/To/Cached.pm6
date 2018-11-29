unit class Pod::To::Cached;

use MONKEY-SEE-NO-EVAL;
use File::Directory::Tree;
use nqp;
use JSON::Fast;

=begin pod

=TITLE Pod::To::Cached

=SUBTITLE Create a precompiled cache of POD files

Module to take a collection of POD files and create a precompiled cache. Methods / functions
to add a POD file to a cache.

=begin SYNOPSIS
use Pod::To::Cached;

my Pod::To::Cached $cache .= new(:path<path-to-cache>, :source<path-to-directory-with-pod-files>);

$cache.update-cache;

for $cache.list-files( :all ).kv -> $filename, $status {
    given $status {
        when Pod::To::Cached::Valid {say "$filename has valid cached POD"}
        when Pod::To::Cached::Updated {say "$filename has valid POD, just updated"}
        when Pod::To::Cached::Tainted {say "$filename has been modified since the cache was last updated"}
        when Pod::To::Cached::Failed {say "$filename has been modified, but contains invalid POD"}
        when Pod::To::Cached::New {say "$filename has not yet been added to pod-cache"}
    }
    user-supplied-routine-for-processing-pod( $cache.pod( $filename ) );
}

# Find files with status
say 'These pod files failed:';
.say for $cache.list-files( Pod::To::Cached::Failed );

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

=item new
    Instantiates class. On instantiation,
        - get the cache from index, or creates a new cache if one does not exist
        - if frozen, does not check the source directory
        - if not frozen, or new cache being created, verifies
            - source directory exists
            - the source directory contains POD/POD6 etc files (recursively)
            - no duplicate pod file names exist, eg. xx.pod & xx.pod6
        - verifies whether the cache is valid

=item update-cache
    All files with Status New or Tainted are precompiled and added to the cache
        - Status is changed to Updated (compiles Valid) or Fail (does not compile)
        - Failed files that were previously Valid files still retain the old cache handle
        - Throws an exception when called on a frozen cache

=item freeze
    Can be called only when there are only Valid or Updated (no New, Tainted or Failed files),
    otherwise dies.
    The intent of this method is to allow the pod-cache to be copied without the original pod-files.
    update-cache will throw an error if used on a frozen cache

=item list-files( Status $s)
    returns an Sequence of files with the given status

=item pod
    method pod(Str $filename, :$when-tainted='none', :when-failed = 'note')
    Returns the POD Object Module generated from the file with the filename.
    When a doc-set is being actively updated, then pod files may be tainted, or failed, and the user may wish
    to choose how to handle them.
    In a frozen cache, all files have valid status
    The behaviour of pod can be changed for 'tainted' or 'failed', eg :when-failed='allow'
        Caution: allowing a failed file uses pod in cache, but will die if the pod is new and failed.
        'note' issues an error on stderr
        'allow' provides pod, no note
        'exit' stops the program at that point
        'none' ignores the pod-name silently

=end pod

constant INDEX = 'file-index.json';
enum Status  is export <New Valid Tainted Updated Failed>;

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
            %!files.map( { .value<status> = Status(.value<status> ) ; .value<added> = DateTime.new( .value<added> ).Instant })
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
    $!precomp = CompUnit::PrecompilationRepository::Default.new(store => $!precomp-store);
    # get handles for all Valid / Tainted files

    for %!files.kv -> $nm, %info {
        next unless %info<status> ~~ any(Valid, Tainted);
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
        $nm = $nm.subst(/ \. \w+ $/, ''); #remove any extension
        if %!files{$nm}:exists {
            if %!files{$nm}<path> eq $pfile {
                # change an Updated status to Valid because re-initialising
                %!files{$nm}<status> = Valid if %!files{$nm}<status> ~~ Updated;
                # detect Tainted
                %!files{$nm}<status> = Tainted if %!files{$nm}<added> < %!files{$nm}<path>.IO.modified;
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

    for %!files.kv -> $pod-name, %info {
        next if %info<status> ~~ any(Valid, Updated);
        note "Processing $pod-name" if $!verbose;
        my $handle;
        try {
            $!precomp.precompile(%info<path>.IO, %info<cache-key>, :force);
            $handle = $!precomp.load(%info<cache-key>)[0];
            CATCH {
                default {
                    @!error-messages.push: "Compile error in $pod-name:\n\t" ~ .Str;
                    $rv = False;
                }
            }
        }
        with $handle {
            %!files{$pod-name}<status handle added> = Updated , $handle, now ;
        }
        else {
            %!files{$pod-name}<status> = Failed;
            note "$pod-name failed to compile" if $!verbose;
            $rv = False; # belt and braces, since this probably should be set in CATCH phaser
            # A new and failed pod will not have a handle
        }
    }
    self.save-index if $rv;
    note ('Cache ' ~ ( $rv ?? '' !! 'not ' ) ~ 'fully updated') if $!verbose;
    $rv # we leave the $!cache-verified flag True because what is in the cache is verified
}

method save-index {
    my %h = :frozen( $!frozen ), :files( (
        gather for %!files.kv -> $fn, %inf {
            if $!frozen {
                take $fn => (
                    :cache-key(%inf<cache-key>),
                    :status( Valid )
                ).hash
            }
            else {
                take $fn => (
                    :cache-key(%inf<cache-key>),
                    :status( %inf<status> ),
                    :added( %inf<added> ),
                    :path(%inf<path>)
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

method pod( Str $filename,
                    :$when-failed = 'note-none', # provide a note, do not supply Pod from cache
                    :$when-tainted = 'allow' # no not, but supply POD (old cache value)
                     ) is export {
    die "Filename <$filename> not in cache" unless $filename ~~ any(%!files.keys);
    sub act-on(Str:D $filename, $behaviour, $message --> Bool) {
        my Bool $rv;
        given $behaviour {
            when / 'allow' / { $rv = False } # no note, and supply POD
            when / 'note' / {
                note "$filename: $message";
                $rv = False; # unless 'note-none' POD is returned
                proceed
            }
            when / 'none'/ { $rv = True } # No POD returned
            when / 'exit' / {
                die "POD called with $behaviour processing <$filename>"
            }
            when / 'note' / {} # test none/exit but do not go to default
            default {
                die "Unknown behaviour $behaviour processing <$filename>"
            }
        }
        $rv
    }

    given %!files{$filename}<status> {
        when Failed {
            return Nil if act-on($filename, $when-failed,
                'failed to compile')
        }
        when Tainted {
            return Nil if act-on($filename, $when-tainted,
                'source pod has been modified')
        }
    }
    =comment Getting here means that the user want to take pod from the cache

    die "Attempt to obtain non-existent POD for <$filename>. Is the source New and Failed?"
        without %!files{$filename}<handle>;
    nqp::atkey(%!files{$filename}<handle>.unit,'$=pod')[0];
}

multi method list-files( Status $s ) {
    gather for %!files.kv -> $pname, %info {
        take $pname if %info<status> ~~ $s
    }
}

multi method list-files( Bool :$all --> Hash) {
    return unless $all;
    ( gather for %.files.kv -> $pname, %info {
        take $pname => %info<status>.Str
    }).hash
}

method freeze( --> Bool ) {
    return if $!frozen;
    my @not-ok = gather for %!files.kv -> $pname, %info {
        take $pname unless %info<status> ~~ any(Valid, Updated )
    }
    die "Cannot freeze because the following are either New, Failed, or Tainted:\n" ~ @not-ok.join("\n\t")
        if +@not-ok;
    $!frozen = True;
    self.save-index;
}
