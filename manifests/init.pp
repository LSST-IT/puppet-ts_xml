class ts_xml(
	String $ts_xml_path,
	Array $ts_xml_subsystems, # This can be either a String or an Array
	Array $ts_xml_languages,
	String $ts_xml_repo,
	String $ts_sal_path,
	String $ts_xml_branch,
	String $ts_xml_build_dir,
	String $ts_xml_user,
	String $ts_xml_group,
){
	vcsrepo { "${ts_xml_path}":
		ensure => present,
		provider => git,
		revision => $ts_xml_branch,
		source => $ts_xml_repo,
		notify => File["${ts_xml_path}"],
		owner => $ts_xml_user,
		group => $ts_xml_group,
	}
	
	file{"${ts_xml_path}":
		ensure => present,
		owner => $ts_xml_user,
		group => $ts_xml_group,
		require => [User[$ts_xml_user] , Group[$ts_xml_group], ],
		#recurse => true,
	}

	file{"${ts_sal_path}/${ts_xml_build_dir}/":
		ensure => directory,
		owner => $ts_xml_user,
		group => $ts_xml_group,
		require => File["${ts_sal_path}"],
	}

	file_line{"Configure SAL workdir environment variable":
		ensure => present,
		line => "export SAL_WORK_DIR=\$LSST_SDK_INSTALL/${ts_xml_build_dir}",
		match => "export SAL_WORK_DIR",
		path => "${ts_sal_path}/setup.env",
	}

	file{ "${ts_sal_path}/${ts_xml_build_dir}/SALSubsystems.xml":
		ensure => present,
		source => "${ts_xml_path}/sal_interfaces/SALSubsystems.xml"
	}
	
	file{ "${ts_sal_path}/${ts_xml_build_dir}/SALGenerics.xml":
		ensure => present,
		source => "${ts_xml_path}/sal_interfaces/SALGenerics.xml"
	}
	
	#Copying xml files to the SAL/test directory and preserving ownernship because of the command above
	$ts_xml_subsystems.each | String $subsystem | {
		exec{"copy-xml-files-${subsystem}":
			path => '/bin:/usr/bin:/usr/sbin',
			command => "find ${ts_xml_path}/sal_interfaces/ -name ${subsystem}_*.xml -exec cp -p {} ${ts_sal_path}/${ts_xml_build_dir}/ \\;",
			require => File["${ts_xml_path}"],
			#execute the command only if the xml aren't in the destination directory
			onlyif => "test $(ls -1 ${ts_sal_path}/${ts_xml_build_dir}/${subsystem}_*.xml 2>/dev/null | wc -l) -eq 0 "
			
		} ~>
		exec {"salgenerator-${subsystem}-validate":
			path => '/bin:/usr/bin:/usr/sbin',
			user => $ts_xml_user,
			group => $ts_xml_group,
			cwd => "${ts_sal_path}/${ts_xml_build_dir}/",
			command => "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} validate'",
			timeout => 0,
			#require => Exec["copy-xml-files-${subsystem}"],
			onlyif => "test $(ls -1 ${ts_sal_path}/${ts_xml_build_dir}/idl-templates/${subsystem}_*.idl 2>/dev/null | wc -l) -eq 0 "
		} ~>
		exec {"salgenerator-${subsystem}-html":
			path => '/bin:/usr/bin:/usr/sbin',
			user => $ts_xml_user,
			group => $ts_xml_group,
			cwd => "${ts_sal_path}/${ts_xml_build_dir}/",
			command => "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} html'",
			timeout => 0,
			onlyif => "test $(ls -1 ${ts_sal_path}/${ts_xml_build_dir}/idl-templates/${subsystem}_*.idl 2>/dev/null | wc -l) -ne 0 "
		}

		$ts_xml_languages.each | String $lang | {
			#Cannot override a variable on puppet, so I'm forced to duplicate each entry in the 'if' condition
			if $lang == "labview"{
				$salgenerator_cmd = "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} ${lang}'"
				$salgenerator_check = "test ! -f ${ts_sal_path}/${ts_xml_build_dir}/${subsystem}/${lang}/sal_${subsystem}.${lang}"
			}elsif $lang == "cpp"{
				$salgenerator_cmd = "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} sal ${lang}'"
				$salgenerator_check = "test ! -f ${ts_sal_path}/${ts_xml_build_dir}/${subsystem}/${lang}/sal_${subsystem}.${lang}"
			}elsif $lang == "html"{
				$salgenerator_cmd = "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} sal ${lang}'"
				$salgenerator_check = "test ! -d ${ts_sal_path}/${ts_xml_build_dir}/${lang}/salgenerator/${subsystem}"
			}elsif $lang == "python"{
				$salgenerator_cmd = "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} sal ${lang}'"
				$salgenerator_check = "test ! -d ${ts_sal_path}/${ts_xml_build_dir}/${subsystem}/${lang}"
			}
			exec{ "salgenerator-${subsystem}-sal-${lang}" :
				path => '/bin:/usr/bin:/usr/sbin',
				user => $ts_xml_user,
				group => $ts_xml_group,
				cwd => "${ts_sal_path}/${ts_xml_build_dir}/",
				command => $salgenerator_cmd,
				timeout => 0,
				require => Exec["salgenerator-${subsystem}-validate"],
				onlyif => $salgenerator_check
			}
			
			if $lang == "python"{
				$onlyif_statement = "test $(ls -1 ${ts_sal_path}/${ts_xml_build_dir}/lib/SALPY_*${subsystem}.so 2>/dev/null | wc -l) -eq 0 "
			}else{
				$onlyif_statement = "test $(ls -1 ${ts_sal_path}/${ts_xml_build_dir}/lib/*${subsystem}.so 2>/dev/null | wc -l) -eq 0 "
			}
			exec {"salgenerator-${subsystem}-lib-${lang}":
				path => '/bin:/usr/bin:/usr/sbin',
				user => $ts_xml_user,
				group => $ts_xml_group,
				cwd => "${ts_sal_path}/${ts_xml_build_dir}/",
				command => "/bin/bash -c 'source ${ts_sal_path}/setup.env ; ${ts_sal_path}/lsstsal/scripts/salgenerator ${subsystem} lib'",
				timeout => 0,
				require => Exec["salgenerator-${subsystem}-sal-${lang}"],
				onlyif => $onlyif_statement
			}
		}
	}

}
