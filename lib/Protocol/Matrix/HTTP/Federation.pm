#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2015 -- leonerd@leonerd.org.uk

package Protocol::Matrix::HTTP::Federation;

use strict;
use warnings;

our $VERSION = '0.02';

use HTTP::Request;

=head1 NAME

C<Protocol::Matrix::HTTP::Federation> - helpers for HTTP messages relating to Matrix federation

=cut

sub new
{
   bless {}, shift;
}

=head1 METHODS

=cut

=head2 make_key_v1_request

   $req = $fed->make_key_v1_request( server_name => $name )

=cut

sub make_key_v1_request
{
   shift;
   my %params = @_;

   return HTTP::Request->new(
      GET => "/_matrix/key/v1",
      [
         Host => $params{server_name},
      ],
   );
}

=head2 make_key_v2_server_request

   $req = $fed->make_key_v2_server_request( server_name => $name, key_id => $id )

=cut

sub make_key_v2_server_request
{
   shift;
   my %params = @_;

   return HTTP::Request->new(
      GET => "/_matrix/key/v2/server/$params{key_id}",
      [
         Host => $params{server_name},
      ],
   );
}

0x55AA;
