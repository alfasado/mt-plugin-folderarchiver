package FolderArchiver::Plugin;

use File::Basename qw( dirname );
use strict;

sub _folder_context {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance();
    my $f = $ctx->stash( 'category' );
    unless ( defined $f ) {
        require MT::Folder;
        my $blog_id = $app->blog->id;
        my $f = MT::Folder->load( { blog_id => $blog_id }, { limit => 1 } );
        if (! defined $f ) {
            $f = MT::Folder->new;
            $f->blog_id( $blog_id );
            $f->id( 0 );
            $f->label( $app->translate( 'Folder' ) );
            $f->description( 'Lorem ipsum dolor sit amet, consectetuer adipiscing elit.' );
        } else {
            $ctx->{ inside_mt_categories } = 1;
        }
        $ctx->{ __stash }{ 'category' } = $f;
        $ctx->stash( 'category', $f );
        $ctx->stash( 'category_id', $f->id );
    }
    $ctx->stash( 'builder' )->build( $ctx, $ctx->stash( 'tokens' ), $cond );
}

sub _cms_post_bulk_save {
    my ( $cb, $app, $folders ) = @_;
    require MT::Request;
    my $r = MT::Request->instance;
    my @rebuild_folders;
    my $old_folders = $r->cache( 'bulk_update_folder_old_folders' );
    if ( ref $folders ) {
        for my $folder ( @$folders ) {
            _post_save_folder( 'cb', $app, $folder, $folder );
            push ( @rebuild_folders, $folder->id );
        }
    }
    if ( ref $old_folders ) {
        for my $folder ( @$old_folders ) {
            my $folder_id = $folder->id;
            if (! grep( /^$folder_id$/, @rebuild_folders ) ) {
                _post_delete_folder( 'cb', $app, $folder, $folder );
            }
        }
    }
    return 1;
}

sub _pre_run {
    my ( $cb, $app ) = @_;
    if ( ref $app eq 'MT::App::CMS' ) {
        if ( my $blog = $app->blog ) {
            if ( $app->mode eq 'bulk_update_folder' ) {
                require MT::Request;
                require MT::Folder;
                my $r = MT::Request->instance;
                my @folders = MT::Folder->load( { blog_id => $blog->id } );
                $r->cache( 'bulk_update_folder_old_folders', \@folders );
            }
        }
        return unless ( $app->mode eq 'delete' );
        my $type = $app->param( 'type' ) || '';
        if ( ( $type eq 'entry' ) || ( $type eq 'page' ) ) {
            my @ids = $app->param( 'id' );
            require MT::Request;
            for my $id ( @ids ) {
                my $r = MT::Request->instance;
                my $self = $r->cache( 'pre_delete_entry_original:' . $id );
                return if $self;
                $r->cache( 'pre_delete_entry_original:' . $id, 1 );
                my $obj = MT->model( $type )->load( $id );
                next unless defined $obj;
                $app->run_callbacks( 'cms_delete_permission_filter.' . $type, $app, $obj );
            }
        }
    }
}

sub _post_save_file_info {
    my ( $cb, $obj, $original ) = @_;
    if ( ( $obj->archive_type eq 'Folder' ) &&
        ( $obj->entry_id ) ) {
        $obj->remove or die $obj->errstr;
    }
}

sub _cms_pre_preview {
    my ( $cb, $app, $preview_tmpl, $data ) = @_;
    if ( my $id = $preview_tmpl->id ) {
        if ( $preview_tmpl->type eq 'page' ) {
            require MT::TemplateMap;
            my $map = MT::TemplateMap->load( { template_id => $id, is_preferred => 1 } );
            if ( $map && ( $map->archive_type eq 'Folder' ) ) {
                my $ctx = $preview_tmpl->context;
                require MT::Folder;
                my $blog_id = $app->blog->id;
                my $f = MT::Folder->load( { blog_id => $blog_id }, { limit => 1 } );
                if (! defined $f ) {
                    $f = MT::Folder->new;
                    $f->blog_id( $blog_id );
                    $f->id( 0 );
                    $f->label( $app->translate( 'Folder' ) );
                    $f->description( 'Lorem ipsum dolor sit amet, consectetuer adipiscing elit.' );
                } else {
                    $ctx->{ inside_mt_categories } = 1;
                }
                $ctx->{ __stash }{ 'category' } = $f;
                $ctx->stash( 'category', $f );
                $ctx->stash( 'category_id', $f->id );
            }
        }
    }
}

sub _call_listing_callback {
    my ( $cb, $obj ) = @_;
    my $app = MT->instance();
    if ( ref $app eq 'MT::App::CMS' ) {
        if ( ( $app->mode eq 'rebuild_new_phase' ) || 
           ( $app->param( 'plugin_action_selector' ) eq 'set_draft' ) ) {
            require MT::Request;
            my $r = MT::Request->instance;
            my $self = $r->cache( 'post_save_entry_original:' . $obj->id );
            return if $self;
            $r->cache( 'post_save_entry_original:' . $obj->id, 1 );
            my $original = $obj->clone_all;
            if ( $app->mode( 'rebuild_new_phase' ) ) {
                $original->status( MT::Entry::HOLD() );
            } elsif ( $app->param( 'plugin_action_selector' ) eq 'set_draft' ) {
                $original->status( MT::Entry::RELEASE() );
            }
            $app->run_callbacks( 'cms_post_save_by_listing.' . $obj->class, $app, $obj, $original );
        }
    }
    return 1;
}

sub _build_file_filter {
    my ( $eh, %args ) = @_;
    my $at    = $args{ ArchiveType };
    my $entry = $args{ Entry };
    my $map = $args{ TemplateMap };
    my $finfo = $args{ FileInfo };
    if ( $at eq 'Folder' ) {
        if ( $entry ) {
            return 0;
        }
    }
    if ( $at eq 'Category' ) {
        if ( $map && $map->build_type == 3 ) {
            if (! $finfo->virtual ) {
                $finfo->virtual( 1 );
                $finfo->save or die $finfo->errstr;
            }
            return 0;
        }
    }
    return 1;
}

sub _post_published_page {
    my ( $cb, $app, $obj ) = @_;
    return 1 if ( $obj->id < 0 );
    if ( $obj->class eq 'page' ) {
        my $folder = $obj->category;
        if ( $folder ) {
            my @fs;
            push ( @fs, $folder );
            _rebuild_folder_archives( $obj->blog, \@fs );
        }
    }
    return 1;
}

sub _pre_delete_page {
    my ( $cb, $app, $obj ) = @_;
    if ( $obj->status != MT::Entry::RELEASE() ) {
        return 1;
    }
    my $f = $obj->category;
    if ( $f ) {
        require MT::Request;
        my $r = MT::Request->instance();
        $r->cache( 'delete_entry_folder:' . $obj->id, $f );
    }
    return 1;
}

sub _post_delete_page {
    my ( $cb, $app, $obj, $original ) = @_;
    return 1 if ( $obj->id < 0 );
    require MT::Request;
    my $r = MT::Request->instance();
    if ( my $folder = $r->cache( 'delete_entry_folder:' . $obj->id ) ) {
        my @fs;
        push ( @fs, $folder );
        _rebuild_folder_archives( $app->blog, \@fs );
    }
}

sub _post_save_page {
    my ( $cb, $app, $obj, $original ) = @_;
    my $change;
    my @folder;
    my $f = $obj->category;
    if ( $f ) {
        push ( @folder, $f );
    }
    if ( defined $original ) {
        my $of = $original->category;
        if ( $of ) {
            push ( @folder, $of );
        }
    }
    my $save;
    if ( scalar @folder ) {
        $obj->save or die $obj->errstr;
        $save = 1;
        _rebuild_folder_archives( $app->blog, \@folder );
    }
}

sub _post_save_folder {
    my ( $cb, $app, $obj, $original ) = @_;
    my @folder;
    push ( @folder, $obj );
    _rebuild_folder_archives( $app->blog, \@folder );
    return 1;
}

sub _rebuild_folder_archives {
    my ( $blog, $folder ) = @_;
    my $app = MT->instance();
    my $site_path = _site_path( $blog );
    require MT::TemplateMap;
    require MT::Template;
    require MT::FileInfo;
    require MT::Page;
    my @maps = MT::TemplateMap->load( { blog_id => $blog->id, archive_type => 'Folder' } );
    return unless scalar @maps;
    my @templates;
    for my $map ( @maps ) {
        my $template = MT::Template->load ( $map->template_id );
        push ( @templates, $template );
    }
    my $fmgr = $blog->file_mgr;
    require MT::Placement;
    require File::Spec;
    for my $f ( @$folder ) {
        my $count = MT::Page->count( { blog_id => $blog->id, status => MT::Entry::RELEASE() },
                                        {
                                            join => [
                                                'MT::Placement', 'entry_id',
                                                { category_id => $f->id },
                                            ],
                                        }
                                    );
        my $i = 0;
        for my $map ( @maps ) {
            my $file_template = $map->file_template;
            my $publish_path = _build_tmpl( $app, $file_template, $blog, $f );
            my $file = File::Spec->catfile( $site_path, $publish_path );
            my $template = $templates[$i];
            if ( $count ) {
                my $build = _build_tmpl( $app, $template->text, $blog, $f,
                                         'Category', $file, $map, $template );
            } else {
                if ( $fmgr->exists( $file ) ) {
                    my $finfo = MT::FileInfo->get_by_key( { file_path => $file,
                                                            blog_id => $blog->id,
                                                            templatemap_id => $map->id,
                                                            template_id => $template->id,
                                                            category_id => $f->id,
                                                            archive_type => 'Category',
                                                            } );
                    if ( $finfo->id ) {
                        $finfo->remove or die $finfo->finfo;
                    }
                    $fmgr->delete( $file );
                }
            }
            $i++;
        }
    }
}

sub _post_delete_folder {
    my ( $cb, $app, $obj, $original ) = @_;
    my $blog = $app->blog;
    return 1 unless defined $blog;
    my $blog_id = $obj->blog_id;
    my $site_path = _site_path( $blog );
    require MT::TemplateMap;
    require MT::FileInfo;
    require File::Spec;
    my @maps = MT::TemplateMap->load( { blog_id => $blog->id, archive_type => 'Folder' } );
    return 1 unless scalar @maps;
    my $fmgr = $blog->file_mgr;
    for my $map ( @maps ) {
        my $file_template = $map->file_template;
        my $publish_path = _build_tmpl( $app, $file_template, $blog, $obj );
        my $file = File::Spec->catfile( $site_path, $publish_path );
        if ( $fmgr->exists( $file ) ) {
            my $finfo = MT::FileInfo->get_by_key( { file_path => $file,
                                                    blog_id => $blog->id,
                                                    templatemap_id => $map->id,
                                                    category_id => $obj->id,
                                                    archive_type => 'Category',
                                                    } );
            if ( $finfo->id ) {
                $finfo->remove or die $finfo->finfo;
            }
            $fmgr->delete( $file );
        }
    }
    return 1;
}

sub _file_info_post_save {
    my ( $cb, $obj ) = @_;
    if ( $obj->entry_id ) {
        if ( $obj->archive_type eq 'Folder' ) {
            $obj->remove or die $obj->errstr;
        }
    }
    return 1;
}

sub _build_tmpl {
    my ( $app, $template, $blog, $category,
         $at, $file, $map, $tmpl ) = @_;
    require MT::Template::Context;
    require MT::FileInfo;
    my $ctx = MT::Template::Context->new;
    $ctx->stash( 'blog', $blog );
    $ctx->stash( 'blog_id', $blog->id );
    $ctx->stash( 'category', $category ) if $category;
    $ctx->stash( 'category_id', $category->id ) if $category;
    $ctx->{ inside_mt_categories } = 1;
    $ctx->stash( 'blog_id', $blog->id );
    my $finfo = MT::FileInfo->new;
    if ( $file ) {
        $finfo = MT::FileInfo->get_by_key( { file_path => $file, blog_id => $blog->id, } );
        $finfo->url( path2url( $file, $blog ) );
        if ( $category ) {
            $finfo->category_id( $category->id );
        } else {
            $finfo->category_id( undef );
        }
        $finfo->archive_type( $at );
        $finfo->template_id( $tmpl->id );
        $finfo->author_id( undef );
        $finfo->templatemap_id( $map->id );
        $finfo->save or die $finfo->errstr;
    }
    if ( $file ) {
        my $filter = MT->run_callbacks(
            'build_file_filter',
            Context      => $ctx,
            context      => $ctx,
            ArchiveType  => $at,
            archive_type => $at,
            TemplateMap  => $map,
            template_map => $map,
            Blog         => $blog,
            blog         => $blog,
            # Entry        => $entry,
            # entry        => $entry,
            FileInfo     => $finfo,
            file_info    => $finfo,
            File         => $file,
            file         => $file,
            Template     => $tmpl,
            template     => $tmpl,
            # PeriodStart  => $start,
            # period_start => $start,
            Category     => $category,
            category     => $category,
            force        => 0
        );
        return 0 unless $filter;
    }
    require MT::Builder;
    my $build = MT::Builder->new;
    my $tokens = $build->compile( $ctx, $template )
        or return $app->error( $app->translate(
            "Parse error: [_1]", $build->errstr) );
    defined( my $html = $build->build( $ctx, $tokens ) )
        or return $app->error( $app->translate(
            "Build error: [_1]", $build->errstr ) );
    return $html unless $file;
    if ( $file ) {
        MT->run_callbacks(
            'build_page',
            Context      => $ctx,
            context      => $ctx,
            ArchiveType  => $at,
            archive_type => $at,
            TemplateMap  => $map,
            template_map => $map,
            Blog         => $blog,
            blog         => $blog,
            # Entry        => $entry,
            # entry        => $entry,
            FileInfo     => $finfo,
            file_info    => $finfo,
            # PeriodStart  => $start,
            # period_start => $start,
            Category     => $category,
            category     => $category,
            RawContent   => \$html,
            raw_content  => \$html,
            Content      => \$html,
            content      => \$html,
            BuildResult  => \$html,
            build_result => \$html,
            Template     => $tmpl,
            template     => $tmpl,
            File         => $file,
            file         => $file
        );
        require File::Basename;
        my $dir = File::Basename::dirname( $file );
        my $fmgr = $blog->file_mgr;
        $dir =~ s!/$!! unless $dir eq '/';
        unless ( $fmgr->exists( $dir ) ) {
            $fmgr->mkpath( $dir );
        }
        unless ( $fmgr->content_is_updated( $file, \$html ) ) {
            return 1;
        }
        my $temp_file = "$file.new";
        $fmgr->put_data( $html, $temp_file );
        $fmgr->rename( $temp_file, $file );
        MT->run_callbacks(
            'build_file',
            Context      => $ctx,
            context      => $ctx,
            ArchiveType  => $at,
            archive_type => $at,
            TemplateMap  => $map,
            template_map => $map,
            Blog         => $blog,
            blog         => $blog,
            # Entry        => $entry,
            # entry        => $entry,
            FileInfo     => $finfo,
            file_info    => $finfo,
            # PeriodStart  => $start,
            # period_start => $start,
            Category     => $category,
            category     => $category,
            RawContent   => \$html,
            raw_content  => \$html,
            Content      => \$html,
            content      => \$html,
            BuildResult  => \$html,
            build_result => \$html,
            Template     => $tmpl,
            template     => $tmpl,
            File         => $file,
            file         => $file
        );
        return 1;
    }
}

sub _site_path {
    my $blog = shift;
    my $site_path = $blog->archive_path;
    $site_path = $blog->site_path unless $site_path;
    require File::Spec;
    my @path = File::Spec->splitdir( $site_path );
    $site_path = File::Spec->catdir( @path );
    return $site_path;
}

sub _site_url {
    my $blog = shift;
    my $site_url = $blog->site_url;
    if ( $site_url =~ /(.*)\/$/ ) {
        $site_url = $1;
    }
    return $site_url;
}

sub path2url {
    my ( $path, $blog ) = @_;
    my $site_path = quotemeta( _site_path( $blog ) );
    my $site_url  = _site_url( $blog );
    $path =~ s/^$site_path/$site_url/;
    $path =~ s!^https*://.*?/!/!;
    return $path;
}

1;