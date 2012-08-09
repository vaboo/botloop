#!/usr/bin/perl

use strict;
use warnings;
use Net::IRC;

my ($net,               $connection,
        $nickname,      $channel,
        $password,      $server,
        $port,          @admins,
);

$net            = new Net::IRC;
$nickname       = 'same';
$port           = 6667;
$server         = 'irc.rizon.net';
$channel        = '#botloop';
$password       = '';
@admins         = ('shelf');

$nickname .= int(rand(1000));

$connection = $net->newconn(
        Server          => "$server",
        Port            => "$port",
        Nick            => "$nickname",
        Username        => "$nickname",
        Ircname         => "$nickname",
) or die ("Can't connect to $server\n");

sub on_public {
        my ($self, $ev) = @_;
        my @to = $ev->to;
        my ($nick) = ($ev->nick);
        my ($arg) = ($ev->args);

        if($arg =~ /\s?same\s?/) { $self->privmsg($channel, 'same'); }
}

sub on_connect {
        my $self = shift;
        $self->privmsg('NickServ', "IDENTIFY $password");
        sleep 1;
        $self->join($channel);
}

sub on_disconnect {
        my $self = shift;
        $self->connect();
}

sub on_kick {
        my $self = shift;
        sleep 10;
        $self->join($channel);
}

sub on_ping {
        my ($self, $ev) = @_;
        my $nick = $ev->nick;
        $self->ctcp_reply($nick, join(' ', ($ev->args)));
}

sub on_version {
        my ($self, $ev) = @_;
        my $nick = $ev->nick;
        $self->ctcp_reply($nick, "VERSION $]");
}

$connection->add_global_handler(376,            \&on_connect);
$connection->add_global_handler('kick',         \&on_kick);
$connection->add_global_handler('cping',        \&on_ping);
$connection->add_global_handler('public',       \&on_public); 
$connection->add_global_handler('cversion',     \&on_version);
$connection->add_global_handler('disconnect',   \&on_disconnect);
$net->start;
