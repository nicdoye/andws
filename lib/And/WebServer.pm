use strict;
use warnings;

use 5.10.0;

package And::WebServer;
use Moose;
use Cwd;
use File::Stat;
use HTTP::Date;
use FileHandle;
use DirHandle;

# use IO::Socket::INET;
# Note: Net::Server is GPL'd so we can't use that.
use Net::Server::NonBlocking;
use And::WebServer::Request;

# Version numbers. I love version numbers.
use vars qw($VERSION);
$VERSION = '0.001';

use constant DEFAULT_PORT    => 1444;
use constant DEFAULT_ADDR    => '127.0.0.1';
use constant DEFAULT_FAMILY  => 'AF_INET';
use constant DEFAULT_TIMEOUT => 5;

use constant ALL_GOOD  => '200 OK';
use constant ENOENT    => '404 Not Found';
use constant EPERM     => '401';
use constant MOAR_BUGS => '500';

#Log::Log4perl->easy_init($DEBUG);

# Will I support changing anything (esp. Port and Addr) after starting up?

# Address to listen on
# IPv6 support may never happen
# 0.0.0.0, 127.0.0.1, ::1
# Defaults to 127.0.0.1
has 'address' => (
    is      => 'rw',
    isa     => 'Str',
    default => And::WebServer::DEFAULT_ADDR,
    reader  => 'get_address',
    writer  => 'set_address'
);

# Port to listen on
# Defaults to 1444
has 'port' => (
    is      => 'rw',
    isa     => 'Int',
    default => And::WebServer::DEFAULT_PORT,
    reader  => 'get_port',
    writer  => 'set_port'
);

# Directory to serve
# Is '.' the right value really?
has 'dir' => (
    is      => 'rw',
    isa     => 'Str',
    default => '.',
    reader  => 'get_dir',
    writer  => 'set_dir'
);

# Have I bound to the port properly?
has 'status' => (
    is      => 'ro',
    isa     => 'Int',
    default => 1,
    reader  => 'get_status',
    writer  => '_set_status'
);

# How does this work with multiple concurrent requests?
has 'request' => (
    is     => 'ro',
    isa    => 'And::WebServer::Request',
    reader => 'get_request',
    writer => 'set_request'
);

has 'logger' => ( is => 'rw', );

# FIXME - use function dispatch instead of all these separate log functions
sub info {
    my ( $self, $function, $message ) = @_;
    $self->logger->info(
        sprintf( "%s::%s %s", $self->meta->name, $function, $message ) );
}

sub warn {
    my ( $self, $function, $message ) = @_;
    $self->logger->warn(
        sprintf( "%s::%s %s", $self->meta->name, $function, $message ) );
}

sub debug {
    my ( $self, $function, $message ) = @_;
    $self->logger->debug(
        sprintf( "%s::%s %s", $self->meta->name, $function, $message ) );
}

sub BUILD {
    my $self = shift;

    # Set up logger
    $self->init_logger();
    $self->set_request( And::WebServer::Request->new() );
    $self->run_server();
}

sub run_server {
    my $self = shift;

    my $server = Net::Server::NonBlocking->new();
    $server->add(
        {   server_name           => $self->meta->name,
            local_address         => $self->get_address,
            local_port            => $self->get_port,
            timeout               => And::WebServer::DEFAULT_TIMEOUT,
            delimiter             => "\n",
            on_connected          => \&client_connected,
            on_disconnected       => \&client_disconnected,
            on_recv_msg           => \&client_message,
            on_connected_param    => [ \$self ],
            on_disconnected_param => [ \$self ],
            on_recv_msg_param     => [ \$self ]
        }
    );

    $self->debug( 'run_server', "Starting server" );

    $server->start;
    $self->debug( 'run_server', "NOTREACHED?" );
}

sub init_logger {
    my $self = shift;
    use Log::Log4perl qw(:easy);
    Log::Log4perl->easy_init($DEBUG);
    $self->logger( Log::Log4perl->get_logger() );

    $self->debug( 'init_logger', "Logger initialized" );
}

# First args are (annoyingly) defined by the Net::Server::NonBlocking object
sub client_connected {
    my $nsnb_self = shift;
    my $client    = shift;
    my $self      = ${ $_[0] };

    use Data::Dumper;
    Dumper($client);
    $self->debug( 'client_connected', "Client connected" );
}

# First args are (annoyingly) defined by the Net::Server::NonBlocking object
sub client_disconnected {
    my $nsnb_self = shift;
    my $client    = shift;
    my $self      = ${ $_[0] };

    $self->debug( 'client_disconnected', "Client disconnected" );
}

# $messages is an array_ref
sub print_client_raw {
    my ( $self, $client, $messages_ref ) = @_;

    $self->debug( 'print_client_raw',
        "Messages length: " . $#{$messages_ref} );
    for my $message ( @{$messages_ref} ) {
        $self->debug( 'print_client_raw', "Sending message: $message" );
        print $client "$message";
    }
}

# $messages is an array_ref
sub print_client {
    my ( $self, $client, $messages_ref ) = @_;

    $self->debug( 'print_client', "Messages length: " . $#{$messages_ref} );
    my @with_new_lines = map {"$_\n"} @{$messages_ref};
    $self->print_client_raw( $client, \@with_new_lines );
}

sub std_headers {
    my ( $self, $client ) = @_;

    $self->print_client(
        $client,
        [   'Date: ' . time2str( time() ),
            'Server: ' . $self->meta->name . "/$VERSION perl/$^V ($^O)",
            "Content-Type: text/html; charset=utf-8"
        ]
    );
}

sub respond {
    my ( $self, $client ) = @_;

    # Only tested on UNIX.
    my $file = $self->get_dir . $self->get_request->get_location;
    $self->debug( 'respond',
        $self->get_dir . $self->get_request->get_location );

    my $stat   = stat($file);
    my $status = $self->get_request->get_protocol . ' ';
    $status .=
        ($stat)
        ? And::WebServer::ALL_GOOD
        : And::WebServer::ENOENT;
    $self->print_client( $client, [ $status ] );
    $self->std_headers($client);

    $self->print_client( $client, [''] );
    print $client '<h1>WAT</h1>' . "\n";
    $self->print_client( $client, [''] );
}

sub the_method_header {
    my ( $self, $message ) = @_;

    my @words = split( / /, $message );
    if ( $#words == 2 ) {
        $self->debug( 'the_method_header', "GET RECEIVED FOR $words[1]" );
        $self->get_request->set_verb( $words[0] );
        $self->get_request->set_location( $words[1] );
        $self->get_request->set_protocol( $words[2] );
    }
    else {
        $self->warn( 'the_method_header', "Invalid GET received: $message" );
        $self->get_request->reset;
    }
}

sub the_host_header {
    my ( $self, $message ) = @_;

    my @words = split( / /, $message );
    if ( $#words == 1 ) {
        $self->debug( 'the_host_header', "HOST: $words[1]" );
        $self->get_request->set_servername( $words[1] );
    }
    else {
        $self->warn( 'the_host_header',
            "Invalid Host line received: $message" );
        $self->get_request->reset;
    }
}

sub the_blank_line {
    my ( $self, $client ) = @_;

    if ( $self->get_request->is_complete ) {
        $self->respond($client);
    }
    else {
        $self->warn( 'the_blank_line', "Not enough HTTP headers set yet" );
        $self->get_request->reset;
    }
}

# First args are (annoyingly) defined by the Net::Server::NonBlocking object
sub client_message {
    my $nsnb_self = shift;
    my $client    = shift;
    my $message   = shift;
    my $self      = ${ $_[0] };

    $self->debug( 'client_message',
        "Received message of length: " . length($message) );

    my $old_input_record_seperator = $/;
    $/ = "\r";
    chomp $message;
    $/ = $old_input_record_seperator;

    $self->debug( 'client_message',
        "Adjusted message to length: " . length($message) );

    # process $message
    $self->debug( 'client_message', "Received message: '${message}'" );

    # FIXME
    # if $message =~ And::WebServer::Request::ALLOWED_METHOD
    # Add rejection of other verbs
    if ( $message =~ /^(GET|HEAD) / ) {
        $self->the_method_header($message);
    }
    elsif ( $message =~ /^Host: / ) {
        $self->the_host_header($message);
    }
    elsif ( $message eq '' ) {
        $self->the_blank_line($client);
    }
    else {
        # Some other header received.
    }
}

=head1 AUTHOR

Nic Doye E<lt>nic@worldofnic.orgE<gt>

=head1 BUGS

None. None whatsoever. (This is a lie).

=head1 LICENSE

   Copyright 2017 Nicolas Doye

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

=cut

1;
