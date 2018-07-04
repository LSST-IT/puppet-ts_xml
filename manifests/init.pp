class ts_xml(
	String $ts_xml_path,
	Array $ts_xml_subsystems, # This can be either a String or an Array
	Array $ts_xml_languages,
	String $ts_xml_repo,
	String $ts_sal_path,
	String $ts_xml_branch = "master",
){
	vcsrepo { "${ts_xml_path}":
		ensure => present,
		provider => git,
		revision => $ts_xml_branch,
		source => $ts_xml_repo,
		notify => File["${ts_xml_path}"],
		owner => "salmgr",
		group => "lsst",
	}
	
	file{"${ts_xml_path}":
		ensure => present,
		owner => 'salmgr',
		group => 'lsst',
		require => [User['salmgr'] , Group['lsst'], ],
		#recurse => true,
	}
	
	#Copying xml files to the SAL/test directory and preserving ownernship because of the command above
	$ts_xml_subsystems.each | String $subsystem | {
		exec{"copy-xml-files-${subsystem}":
			path => '/bin:/usr/bin:/usr/sbin',
			command => "find ${ts_xml_path}/sal_interfaces/ -name ${subsystem}_*.xml -exec cp -p {} ${ts_sal_path}/test/ \\;",
			require => File["${ts_xml_path}"],
			#execute the command only if the xml aren't in the destination directory
			onlyif => "test $(ls -1 ${ts_sal_path}/test/${subsystem}_*.xml 2>/dev/null | wc -l) -eq 0 "
			
		}
		exec {"salgenerator-${subsystem}-validate":
			path => '/bin:/usr/bin:/usr/sbin',
			user => "salmgr",
			group => "lsst",
			cwd => "${ts_sal_path}/test/",
			command => "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} validate'",
			timeout => 0,
			require => Exec["copy-xml-files-${subsystem}"],
			onlyif => "test $(ls -1 ${ts_sal_path}/test/idl-templates/${subsystem}_*.idl 2>/dev/null | wc -l) -eq 0 "
		}

		$ts_xml_languages.each | String $lang | {
			#Cannot override a variable on puppet, so I'm forced to duplicate each entry in the 'if' condition
			if $lang == "labview"{
				$salgenerator_cmd = "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} ${lang}'"
				$salgenerator_check = "test ! -f ${ts_sal_path}/test/${subsystem}/${lang}/sal_${subsystem}.${lang}"
			}elsif $lang == "cpp"{
				$salgenerator_cmd = "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} sal ${lang}'"
				$salgenerator_check = "test ! -f ${ts_sal_path}/test/${subsystem}/${lang}/sal_${subsystem}.${lang}"
			}elsif $lang == "html"{
				$salgenerator_cmd = "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} sal ${lang}'"
				$salgenerator_check = "test ! -f ${ts_sal_path}/test/${lang}/${subsystem}"
			}elsif $lang == "python"{
				$salgenerator_cmd = "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} sal ${lang}'"
				$salgenerator_check = "test ! -f ${ts_sal_path}/test/${subsystem}/${lang}/${subsystem}*.py"
			}
			exec{ "salgenerator-${subsystem}-sal-${lang}" :
				path => '/bin:/usr/bin:/usr/sbin',
				user => "salmgr",
				group => "lsst",
				cwd => "${ts_sal_path}/test/",
				command => $salgenerator_cmd,
				timeout => 0,
				require => Exec["salgenerator-${subsystem}-validate"],
				onlyif => $salgenerator_check
			}
			
			exec {"salgenerator-${subsystem}-lib-${lang}":
				path => '/bin:/usr/bin:/usr/sbin',
				user => "salmgr",
				group => "lsst",
				cwd => "${ts_sal_path}/test/",
				command => "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} lib'",
				timeout => 0,
				require => Exec["salgenerator-${subsystem}-sal-${lang}"],
				onlyif => "test $(ls -1 ${ts_sal_path}/test/lib/*${subsystem}.so 2>/dev/null | wc -l) -eq 0 "
			}
		}
	}

}