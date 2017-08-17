use strict;
use warnings;

use 5.14.0;

package And::WebServer;
use And::WebServer::Request;
use Cwd;
use DirHandle;
use Fcntl qw/:mode/;
use File::stat;
use File::MimeInfo::Magic;
use HTTP::Date;
use IO::File;
use Moose;
use Net::Server::NonBlocking;
use Time::localtime;
use User::grent;
use User::pwent;

use experimental qw/switch/;

# Version numbers. I love version numbers.
use vars qw($VERSION);
$VERSION = '0.005';

use constant DEFAULT_PORT    => 1444;
use constant DEFAULT_ADDR    => '127.0.0.1';
use constant DEFAULT_FAMILY  => 'AF_INET';
use constant DEFAULT_TIMEOUT => 1;

use constant HTTP_OK                      => '200 OK';
use constant E_HTTP_NOT_FOUND             => '404 Not Found';
use constant E_HTTP_FORBIDDEN             => '403 Forbidden';
use constant E_HTTP_METHOD_NOT_ALLOWED    => '405 Method Not Allowed';
use constant E_HTTP_INTERNAL_SERVER_ERROR => '500 Internal Server Error';

use constant ALLOWED_METHODS => {
    'GET'     => 1,
    'HEAD'    => 1,
    'POST'    => 0,
    'PUT'     => 0,
    'DELETE'  => 0,
    'CONNECT' => 0,
    'OPTIONS' => 0,
    'TRACE'   => 0,
    'PATCH'   => 0
};

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
has 'document_root' => (
    is      => 'rw',
    isa     => 'Str',
    default => '.',
    reader  => 'get_document_root',
    writer  => 'set_document_root'
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

sub me {
    my $self = shift;
    $self->meta->name . "/$VERSION perl/$^V ($^O)";
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
            'Server: ' . $self->meta->name . "/$VERSION perl/$^V ($^O)"
        ]
    );
}

# Just print all the remaining headers and a blank line
sub final_headers {
    my ( $self, $client, $messages_ref ) = @_;
    push @$messages_ref, '';
    $self->print_client( $client, $messages_ref );
}

sub error_page {
    my ( $self, $client, $error ) = @_;

    $self->final_headers( $client,
        ['Content-Type: text/html; charset=utf-8'] );

    $self->print_client( $client,
        [ '<h1>' . $error . '</h1>', '<hr/>', '<i>' . $self->me . '</i>' ] );
}

sub file_type {
    my ( $self, $mode ) = @_;

# Other filesystem/OS combinations may support other types of file (e.g. door (D) on Solaris)
    given ($mode) {
        'l' when ( S_ISLNK($_) );
        'd' when ( S_ISDIR($_) );
        'c' when ( S_ISCHR($_) );
        'b' when ( S_ISBLK($_) );
        's' when ( S_ISSOCK($_) );
        'p' when ( S_ISFIFO($_) );
        '-' when ( S_ISREG($_) );
        default { '?'; }
    }
}

sub file_perms {
    my ( $self, $mode ) = @_;
    my $answer = '---------';

# If anyone can tell me why this doesn't work, I'd love to know. ($_ & S_I*) always fails
#
# given ($mode) {
#     when ( $_ & S_IRUSR ) { substr( $answer, 0, 1 ) = 'r'; continue; }
#     when ( $_ & S_IWUSR ) { substr( $answer, 1, 1 ) = 'w'; continue; }
#     when ( $_ & S_IXUSR ) { substr( $answer, 2, 1 ) = 'x'; continue; }
#     when ( $_ & S_IRGRP ) { substr( $answer, 3, 1 ) = 'r'; continue; }
#     when ( $_ & S_IWGRP ) { substr( $answer, 4, 1 ) = 'w'; continue; }
#     when ( $_ & S_IXGRP ) { substr( $answer, 5, 1 ) = 'x'; continue; }
#     when ( $_ & S_IROTH ) { substr( $answer, 6, 1 ) = 'r'; continue; }
#     when ( $_ & S_IWOTH ) { substr( $answer, 7, 1 ) = 'w'; continue; }
#     when ( $_ & S_IXOTH ) { substr( $answer, 8, 1 ) = 'x'; continue; }
# }
    if ( $mode & S_IRUSR ) { substr( $answer, 0, 1 ) = 'r'; }
    if ( $mode & S_IWUSR ) { substr( $answer, 1, 1 ) = 'w'; }
    if ( $mode & S_IXUSR ) { substr( $answer, 2, 1 ) = 'x'; }
    if ( $mode & S_IRGRP ) { substr( $answer, 3, 1 ) = 'r'; }
    if ( $mode & S_IWGRP ) { substr( $answer, 4, 1 ) = 'w'; }
    if ( $mode & S_IXGRP ) { substr( $answer, 5, 1 ) = 'x'; }
    if ( $mode & S_IROTH ) { substr( $answer, 6, 1 ) = 'r'; }
    if ( $mode & S_IWOTH ) { substr( $answer, 7, 1 ) = 'w'; }
    if ( $mode & S_IXOTH ) { substr( $answer, 8, 1 ) = 'x'; }

    return $answer;
}

sub html_format_dirent {
    my ( $self, $dir, $dirent ) = @_;

    chop $dir if ( $dir =~ /\/$/ );

    my $actual_file = "$dir/$dirent";
    my $link_file   = $actual_file;

    # Dirty hack
    my $root_dir_for_regex = $self->get_document_root;
    $link_file =~ s/^${root_dir_for_regex}//;

    $self->debug( 'html_format_dirent',
        $self->get_document_root . " $dir $dirent" );

    my $stat = stat($actual_file);

    my $permstring
        = $self->file_type( $stat->mode ) . $self->file_perms( $stat->mode );

    my $owner = getpwuid( $stat->uid )->name;
    my $group = getgrgid( $stat->gid )->name;
    my $size  = $stat->size;
    my $mtime = $stat->mtime;

    sprintf( "<li><pre>%s\t%s\t%s\t%s\t%s\t<a href='%s'>%s</a></pre></li>",
        $permstring, $owner, $group, $size, ctime($mtime), $link_file,
        $dirent );
}

sub directory_page {
    my ( $self, $client, $dirname ) = @_;

    # FIXME - no permissions check
    my $dh = DirHandle->new($dirname);
    if ( defined $dh ) {
        $self->final_headers( $client,
            ['Content-Type: text/html; charset=utf-8'] );
        $self->print_client( $client, ['<ul>'] );
        while ( defined( my $dirent = $dh->read ) ) {
            my $stat = stat($dirent);
            $self->print_client( $client,
                [ $self->html_format_dirent( $dirname, $dirent ) ] );
        }
        $self->print_client( $client, ['</ul>'] );

        undef $dh;
    }
    else {
        # FIXME - this error is too generic.
        $self->error_page( $client,
            And::WebServer::E_HTTP_INTERNAL_SERVER_ERROR );
    }
}

sub content_type {
    my ( $self, $file ) = @_;
    my $mime_type = mimetype($file);

    return 'text/plain' unless ( defined $mime_type );
    given ($mime_type) {
        'text/html; charset=utf-8' when ('text/html');
        'text/plain' when {''};
        default {$mime_type}
    }
}

sub file_page {
    my ( $self, $client, $file ) = @_;

    my $mime_type    = mimetype($file);
    my $content_type = $self->content_type($file);

    my $fh = IO::File->new( $file, 'r' );
    if ( defined $fh ) {
        $fh->binmode;
        $self->final_headers( $client, ["Content-Type: $content_type"] );

        while (<$fh>) {
            $self->print_client_raw( $client, [$_] );
        }
        $fh->close;
    }
    else {
        # FIXME - this error is too generic.
        $self->error_page( $client,
            And::WebServer::E_HTTP_INTERNAL_SERVER_ERROR );
    }
}

sub normal_page {
    my ( $self, $client, $file ) = @_;

    # We can add more headers into this if need be
    # And alter this if we decide to display non-html media

    if ( -f $file ) {
        $self->file_page( $client, $file );
    }
    elsif ( -d $file ) {
        $self->directory_page( $client, $file );
    }
    else {
        $self->final_headers( $client,
            ['Content-Type: text/html; charset=utf-8'] );
        $self->print_client(
            $client,
            [   "<h1>You have requested $file</h1>",
                '<p>Sadly, it is is neither a regular file nor a directory.</p>'
            ]
        );
    }
}

sub respond {
    my ( $self, $client ) = @_;

    # Only tested on UNIX.
    my $file = $self->get_document_root . $self->get_request->get_location;
    $self->debug( 'respond',
        $self->get_document_root . $self->get_request->get_location );

    my $stat        = stat($file);
    my $state       = 0;
    my $status_line = $self->get_request->get_protocol . ' ';
    if ( ALLOWED_METHODS->{ $self->get_request->get_verb } ) {
        if ($stat) {
            $state = And::WebServer::HTTP_OK;
        }
        else {
            $state = And::WebServer::E_HTTP_NOT_FOUND;
        }
    }
    else {
        $state = And::WebServer::E_HTTP_METHOD_NOT_ALLOWED;
    }

    $status_line .= $state;
    $self->print_client( $client, [$status_line] );
    $self->std_headers($client);
    if ( $state eq And::WebServer::HTTP_OK ) {
        $self->normal_page( $client, $file );
    }
    else {
        $self->error_page( $client, $state );
    }
}

sub the_method_header {
    my ( $self, $message ) = @_;

    my @words = split( / /, $message );

    if ( $#words == 2 ) {
        $self->debug( 'the_method_header',
            "$words[0] RECEIVED FOR $words[1]" );
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

    my ($first) = split / /, $message;
    if ( not defined $first ) {

        # Blank line, means the split on $message doesn't define £first
        $self->the_blank_line($client);
    }
    elsif ( exists( ALLOWED_METHODS->{$first} ) ) {

        # Matched a know http method
        $self->the_method_header($message);
    }
    elsif ( $first eq 'Host:' ) {
        $self->the_host_header($message);
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
