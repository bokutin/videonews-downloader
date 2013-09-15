package App::MirrorVideonews::Blob::WMV50;

use Moose;
use namespace::autoclean;

with qw(App::MirrorVideonews::Role::Blob App::MirrorVideonews::TraitFor::Blob::WindowsMedia);

sub can_handle_uri {
    my ($class, $uri) = @_;

    $uri =~ m/\D50\D*\.wmv$/i;
}

__PACKAGE__->meta->make_immutable; no Moose; 1;