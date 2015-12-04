push our @EXPORT, qw( matrix_create_filter );

=head2 matrix_create_filter

   my ( $filter_id ) = matrix_create_filter( $user, \%filter )->get;

Creates a new filter for the user. Returns the filter id of the new filter.

=cut

sub matrix_create_filter
{
   my ( $user, $filter ) = @_;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/v2_alpha/user/:user_id/filter",
      content => $filter,
   )->then( sub {
      my ( $body ) = @_;

      assert_json_keys( $body, "filter_id" );

      Future->done( $body->{filter_id} )
   })
}


test "Can create filter",
   requires => [ local_user_fixture( with_events => 0 ) ],

   proves => [qw( can_create_filter )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_filter( $user, {
         room => { timeline => { limit => 10 } },
      });
   };


test "Can download filter",
   requires => [
      local_user_fixture( with_events => 0 ),
      qw( can_create_filter )
   ],

   check => sub {
      my ( $user ) = @_;

      matrix_create_filter( $user, {
         room => { timeline => { limit => 10 } }
      })->then( sub {
         my ( $filter_id ) = @_;

         do_request_json_for( $user,
            method  => "GET",
            uri     => "/v2_alpha/user/:user_id/filter/$filter_id",
         )
      })->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, "room" );
         assert_json_keys( my $room = $body->{room}, "timeline" );
         assert_json_keys( my $timeline = $room->{timeline}, "limit" );
         $timeline->{limit} == 10 or die "Expected timeline limit to be 10";

         Future->done(1)
      })
   };
