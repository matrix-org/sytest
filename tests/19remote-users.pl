# How many more users do we want?
my $REMOTE_USERS = 2;

prepare "Remote users",
   requires => [qw( http_clients can_register )],

   do => sub {
      my ( $clients ) = @_;
      my $http = $clients->[1];

      Future->needs_all( map {
         my $uid = "19remote-users-$_";

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
      } 1 .. $REMOTE_USERS
      )->then( sub {
         my @users = @_;

         provide remote_users => \@users;

         Future->done();
      });
   };
