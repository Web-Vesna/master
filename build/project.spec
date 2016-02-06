%define homepath %{__libdir}/apek-energo

Name:		apek-energo
Version:	1
Release:	2
Source:		https://github.com/Web-Vesna/master/archive/apek-energo-release-%{version}-%{release}.tar.gz
Summary:	Apek-Energo project
Group:		Applications/Multimedia
Url:		https://github.com/Web-Vesna/master
Packager:	Pavel Berezhnoy <p.berezhnoy@web-vesna.ru>
BuildRoot:	%{_tmppath}/%{name}-root
BuildArch:	noarch

%description

Nothing interesting

%package data

Summary:	Apek-Energo data daemon
Version:	1
Release:	1
Group:		Applications/Multimedia
BuildArch:	noarch

%description

Daemon works with database engine and provides an access to low-level logic.

%package front

Summary:	Apek-Energo frontend daemon
Version:	1
Release:	1
Group:		Applications/Multimedia
BuildArch:	noarch

%description

Apek-Energo project frontend part

%package session

Summary:	Apek-Energo session daemon
Version:	1
Release:	1
Group:		Applications/Multimedia
BuildArch:	noarch

%description

Daemon enables a session mechanism for Apek-Energo project

%package logic

Summary:	Apek-Energo proxy daemon
Version:	1
Release:	1
Group:		Applications/Multimedia
BuildArch:	noarch

%description

Daemon implements a proxy between frontend and data

%package files

Summary:	Apek-Energo files daemon
Version:	1
Release:	1
Group:		Applications/Multimedia
BuildArch:	noarch

%description

Daemon implements a files interface for Apek-Energo project

#################

%prep

# Generate a files list for any package
find data -type f \( -name '*.pl' -o -name '*.pm' -o -name 'data' \)

#################

%files

# Nothing to do

%files data -f data.files

%files front -f front.files

%files session -f session.files

%files logic -f logic.files

%files files -f files.files


