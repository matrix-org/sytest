our @EXPORT = qw( User is_User do_request_json_for );

# A handy little structure for other scripts to find in 'user' and 'more_users'
struct User =>
   [qw( http user_id access_token refresh_token eventstream_token saved_events pending_get_events )],
   predicate => 'is_User';

*do_request_json_for = \&MatrixAPIHelpers::do_request_json_for;

# Put these API helpers in their own package so that croak works nicely
package MatrixAPIHelpers;

use Carp;

sub do_request_json_for
{
   my ( $user, %args ) = @_;

   ::is_User( $user ) or croak 'Expected a User to do_request_json_for';

   my $user_id = $user->user_id;
   ( my $uri = delete $args{uri} ) =~ s/:user_id/$user_id/g;

   my %params = (
      access_token => $user->access_token,
      %{ delete $args{params} || {} },
   );

   $user->http->do_request_json(
      uri    => $uri,
      params => \%params,
      %args,
   );
}
