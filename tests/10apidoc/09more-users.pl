# How many more users do we want?
my $LOCAL_USERS = 3;

prepare "More local users",
   requires => [qw( first_http_client user can_register )],

   provides => [qw( more_users local_users )],

   do => sub {
      my ( $http, $user ) = @_;

      Future->needs_all( map {
         my $uid = "09more-users-$_";

         $http->do_request_json(
            method => "POST",
            uri    => "/register",

            content => {
               type     => "m.login.password",
               user     => $uid,
               password => "an0th3r s3kr1t",
            },
         )->then( sub {
            my ( $body ) = @_;
            my ( $user_id, $access_token ) = @{$body}{qw( user_id access_token )};

            $http->do_request_json(
               method => "GET",
               uri    => "/events",
               params => { access_token => $access_token, timeout => 0 },
            )->then( sub {
               my ( $body ) = @_;

               Future->done( User( $http, $user_id, $access_token, $body->{end}, [], undef ) );
            });
         });
      } 1 .. $LOCAL_USERS
      )->then( sub {
         my @users = @_;

         provide more_users => \@users;
         provide local_users => [ $user, @users ];

         Future->done();
      })
   };
