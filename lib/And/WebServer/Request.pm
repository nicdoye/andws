use strict;
use warnings;

use 5.10.0;

package And::WebServer::Request;
use Moose;
use constant OTHER_HEADER => 'Host:';

has 'verb' => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
    reader  => 'get_verb',
    writer  => 'set_verb'
);

has 'protocol' => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
    reader  => 'get_protocol',
    writer  => 'set_protocol'
);

has 'location' => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
    reader  => 'get_location',
    writer  => 'set_location'
);

has 'servername' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'localhost',
    reader  => 'get_servername',
    writer  => 'set_servername'
);

sub reset {
    my $self = shift;

    $self->set_verb('');
    $self->set_protocol('');
    $self->set_location('');
    $self->set_servername('');
}

# Return true if the request is valid
sub is_complete {
    my $self = shift;

    if ( $self->get_verb && $self->get_location and $self->get_protocol ) {
        return ( $self->get_servername
                || ( $self->get_protocol == 'HTTP/1.0' ) );
    }
}

1;
