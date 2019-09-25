use JSON qw( decode_json );

sub matrix_deactivate_account
{
   my ( $user, %opts ) = @_;

   # use the user's password unless one was given in opts
   my $password = (delete $opts{password}) // $user->password;

   do_request_json_for( $user,
      method  => "POST",
      uri     => "/r0/account/deactivate",
      content => {
         auth => {
            type     => "m.login.password",
            user     => $user->user_id,
            password => $password,
         },
         %opts,
      },
   );
}
push our @EXPORT, qw( matrix_deactivate_account );

test "Can deactivate account",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_deactivate_account( $user );
   };

test "Can't deactivate account with wrong password",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_deactivate_account( $user, password=>"wrong password" )
      ->main::expect_http_401->then( sub {
         my ( $resp ) = @_;

         my $body = decode_json $resp->content;

         assert_json_keys( $body, qw( error errcode params completed flows ));

         my $errcode = $body->{errcode};

         $errcode eq "M_FORBIDDEN" or
            die "Expected errcode to be M_FORBIDDEN but was $errcode";

         Future->done(1);
      });
   };

test "After deactivating account, can't log in with password",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_deactivate_account( $user )
      ->then( sub {
         do_request_json_for( $user,
            method  => "POST",
            uri     => "/r0/login",
            content => {
               type     => "m.login.password",
               user     => $user->user_id,
               password => $user->password,
            }
         # We don't mandate the exact failure code here
         # (that should be done in the login test if
         # anywhere), any 4xx code is fine as far as
         # this test is concerned.
         )->main::expect_http_4xx;
      });
   };
