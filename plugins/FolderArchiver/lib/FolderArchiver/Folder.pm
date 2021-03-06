package FolderArchiver::Folder;
use strict;
use base qw( MT::ArchiveType::Page );
use MT::Folder;
use MT::Request;

sub name {
    return 'Folder';
}

sub archive_label {
    MT->translate( 'Folder' );
}

sub default_archive_templates {
    return [
        {
            label    => 'folder/sub-folder/index.html',
            template => '<MTParentFolders glue="/"><MTFolderBasename></MTParentFolders>/index.html',
            default  => 1,
        },
    ];
}

sub archive_file {
    my $app = MT->instance;
    return 0 if ( ref $app ne 'MT::App::CMS' );
    return 0 if ( $app->mode ne 'rebuild' );
    my $r = MT::Request->instance;
    my $rebuild_folder = $r->cache( 'rebuild_folder' );
    return if $rebuild_folder;
    my $blog = $app->blog;
    return unless $blog;
    my @folder = MT::Folder->load( { blog_id => $blog->id } );
    if ( scalar @folder ) {
        require FolderArchiver::Plugin;
        FolderArchiver::Plugin::_rebuild_folder_archives( $blog, \@folder );
    }
    $r->cache( 'rebuild_folder', 1 );
    return '';
}

sub archive_group_iter {

}

sub archive_group_entries {

}

sub archive_entries_count {
    return 0;
}

1;