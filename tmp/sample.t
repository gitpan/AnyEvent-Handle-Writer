#!/usr/bin/env perl

BEGIN {
unless ($ENV{PERL_ANYEVENT_NET_TESTS}) {
   #print "1..0 # Skip PERL_ANYEVENT_NET_TESTS environment variable not set\n";
   #exit 0;
}
}
use Test::More tests => 4;
use common::sense;
use lib::abs '../lib';
use AnyEvent;
use AnyEvent::Handle::Writer;
use AnyEvent::Socket;

my $chunk = 8;
my $file = lib::abs::path('data');
my $size = -s $file;
#my $file = '/dev/urandom';
#my $size = 1024;

for my $ssl (1,0) {
for my $write_sub (1,0) {
diag "\nstarting ssl=$ssl, sub=$write_sub";
my $cv = AE::cv;
my $c;$c = tcp_connect 'www.google.com',$ssl ? 443 : 80 ,sub {
   my $fh = shift or die "$!";
   my $state = 0;
   my $h = AnyEvent::Handle::Writer->new(
      fh          => $fh,
      timeout     => 3,
      on_error    => sub { my $h = shift;fail "got an error";diag "error: @_";$h->destroy;$cv->send; },
      on_drain    => sub { my $h = shift;#diag "got a drain on ".int $h;
         is $state, 0, 'initial on_drain';
      },
   );
   $h->starttls('connect') if $ssl;
   $h->on_drain( undef );
   $state = 1;
   my $data = "POST / HTTP/1.0\015\012Host: www.google.com\015\012Content-length: $size\015\012\015\012";
   if ($write_sub) {
      $h->push_write(sub{
         my $h = shift;
         diag "call sub write";
         if ($h->{tls}) {
            # Don't want to encode data by myself when using tls.
            # Return this job to handle
            if (length $data) {
               $h->unshift_write(substr($data,0,$chunk,''));
               return 0; # call me again
            } else {
               return 1; # I'm done
            }
         } else {
            my $len = syswrite($h->{fh}, $data); # Here may be sendfile
            if (defined $len) {
               diag "written $len";
               substr $data, 0, $len, "";
               if (length $data) {
                  return 0; # want be called again
               } else {
                  return 1; # done
               }
            } elsif (!$!{EAGAIN} and !$!{EINTR} and !$!{WSAEWOULDBLOCK}) {
               $h->_error ($!, 1);
               return 1; # No more requests to me, got an error
            }
            return 0;
         }
      });
   } else {
      $h->push_write($data);
   }
   $h->push_sendfile($file,$size);
   $h->push_read(line => qr{\015\012}, sub {
      shift;
      is $_[0], 'HTTP/1.0 302 Found', "ssl=$ssl, sub=$write_sub";
      $h->destroy;
      $cv->send;
   });
};

$cv->recv;
last;
}
}

