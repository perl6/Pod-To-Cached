use v6.*;
use nqp;
class CompUnit::PrecompilationRepository::Document is CompUnit::PrecompilationRepository::Default {
    
    method !load-handle-for-path(CompUnit::PrecompilationUnit $unit) {
            my $preserve_global := nqp::ifnull(nqp::gethllsym('perl6', 'GLOBAL'), Mu);
            if $*RAKUDO_MODULE_DEBUG -> $RMD { $RMD("Loading precompiled\n$unit") }
            my $handle := CompUnit::Loader.load-precompilation-file($unit.bytecode-handle);
            $unit.close;
            nqp::bindhllsym('perl6', 'GLOBAL', $preserve_global);
            CATCH {
                default {
                    nqp::bindhllsym('perl6', 'GLOBAL', $preserve_global);
                    .throw;
                }
            }
            $handle
        }

    method !load-file(
            CompUnit::PrecompilationStore @precomp-stores,
            CompUnit::PrecompilationId $id,
            :$repo-id,
        ) {
            my $compiler-id = CompUnit::PrecompilationId.new-without-check($*PERL.compiler.id);
            my $RMD = $*RAKUDO_MODULE_DEBUG;
            for @precomp-stores -> $store {
                $RMD("Trying to load {$id ~ ($repo-id ?? '.repo-id' !! '')} from $store.prefix()") if $RMD;
                my $file = $repo-id
                    ?? $store.load-repo-id($compiler-id, $id)
                    !! $store.load-unit($compiler-id, $id);
                return $file if $file;
            }
            Nil
    }

#    #| Loads a file, returns a handle for precompiled file and checksum. Needs an $id for the precompilation unit, an IO::Path and an array of Compunit::Precompilation store that is assigned by default
#    multi method load-x(
#        CompUnit::PrecompilationId $id,
#        IO::Path :$source,
#        CompUnit::PrecompilationStore :@precomp-stores = Array[CompUnit::PrecompilationStore].new($.store),
#    ) {
#        my $compiler-id = CompUnit::PrecompilationId.new-without-check($*PERL.compiler.id);
#        my $unit = self!load-file(@precomp-stores, $id);
#        if $unit {
#            return (self!load-handle-for-path($unit), $unit.checksum);
#        }
#        else {
#            $unit.close;
#        }
#        Nil
#    }
}
