my $content_id;

test "Can upload without a file name",
   requires => [ local_user_fixture() ],

   do => sub {
      my ( $user ) = @_;

      upload_test_content( $user, )->then( sub {
         ( $content_id ) = @_;
         Future->done(1)
      });
   };

# These next two tests do the same thing with two different HTTP clients, to
# test locally and via federation

sub test_using_client
{
   my ( $client ) = @_;

   get_media( $client, $content_id )->then( sub {
      my ( $disposition ) = @_;

      defined $disposition and
         die "Unexpected Content-Disposition header";

      Future->done(1);
   });
}

test "Can download without a file name locally",
   requires => [ $main::API_CLIENTS[0] ],

   check => sub {
      my ( $http ) = @_;
      test_using_client( $http );
   };

test "Can download without a file name over federation",
   requires => [ $main::API_CLIENTS[1] ],

   check => sub {
      my ( $http ) = @_;
      test_using_client( $http );
   };
