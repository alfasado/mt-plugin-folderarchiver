<?php
function smarty_block_mtsetfoldercontext ( $args, $content, &$ctx, &$repeat ) {
    $folder = $ctx->stash( 'category' );
    if (! $folder ) $folder = $ctx->stash( 'archive_category' );
    if (! $folder ) {
        if (! isset( $content ) ) {
            $mt = $ctx->mt;
            $path = NULL;
            if ( !$path && $_SERVER[ 'REQUEST_URI' ] ) {
                $path = $_SERVER[ 'REQUEST_URI' ];
                // strip off any query string...
                $path = preg_replace( '/\?.*/', '', $path );
                // strip any duplicated slashes...
                $path = preg_replace( '!/+!', '/', $path );
            }
            if ( preg_match( '/IIS/', $_SERVER[ 'SERVER_SOFTWARE' ] ) ) {
                if ( preg_match( '/^\d+;( .* )$/', $_SERVER[ 'QUERY_STRING' ], $matches ) ) {
                    $path = $matches[1];
                    $path = preg_replace( '!^http://[^/]+!', '', $path );
                    if ( preg_match( '/\?( .+ )?/', $path, $matches ) ) {
                        $_SERVER[ 'QUERY_STRING' ] = $matches[1];
                        $path = preg_replace( '/\?.*$/', '', $path );
                    }
                }
            }
            $path = preg_replace( '/\\\\/', '\\\\\\\\', $path );
            $pathinfo = pathinfo( $path );
            $ctx->stash( '_basename', $pathinfo[ 'filename' ] );
            if ( isset( $_SERVER[ 'REDIRECT_QUERY_STRING' ] ) ) {
                $_SERVER[ 'QUERY_STRING' ] = getenv( 'REDIRECT_QUERY_STRING' );
            }
            if ( preg_match( '/\.( \w+ )$/', $path, $matches ) ) {
                $req_ext = strtolower( $matches[1] );
            }
            $data = $mt->resolve_url( $path );
            $cat = $data->fileinfo_category_id;
            $archive_category = $mt->db()->fetch_folder( $cat );
            $ctx->stash( 'category', $archive_category );
            $ctx->stash( 'archive_category', $archive_category );
        }
    }
    return $content;
}
?>