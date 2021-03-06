package Helpers;

use base Exporter;

our @EXPORT_OK = qw(
    check_params
    return_500
);

our %EXPORT_TAGS = ( all => [ @EXPORT_OK ] );

sub check_params {
    my $self = shift;

    my $p = $self->req->params->to_hash;
    for (@_) {
        return $self->render(status => 400, json => { error => sprintf "%s field is required", ucfirst }) && undef unless $p->{$_};
    }

    return $p;
}

sub _i_err {
    my $self = shift;
    return $self->render(json => { status => 500, error => 'internal' });
}

sub render_500 {
    return $self->_i_err;
}

