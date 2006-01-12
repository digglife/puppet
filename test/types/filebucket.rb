if __FILE__ == $0
    $:.unshift '..'
    $:.unshift '../../lib'
    $puppetbase = "../../../../language/trunk"
end

require 'puppet'
require 'test/unit'
require 'fileutils'
require 'puppettest'

# $Id$

class TestFileBucket < Test::Unit::TestCase
	include FileTesting
    # hmmm
    # this is complicated, because we store references to the created
    # objects in a central store
    def mkfile(hash)
        file = nil
        assert_nothing_raised {
            file = Puppet.type(:file).create(hash)
        }
        return file
    end

    def mkbucket(name,path)
        bucket = nil
        assert_nothing_raised {
            bucket = Puppet.type(:filebucket).create(
                :name => name,
                :path => path
            )
        }

        @@tmpfiles.push path

        return bucket
    end

    def mktestfile
        # because luke's home directory is on nfs, it can't be used for testing
        # as root
        tmpfile = tempfile()
        File.open(tmpfile, "w") { |f| f.puts rand(100) }
        @@tmpfiles.push tmpfile
        mkfile(:name => tmpfile)
    end

    def setup
        super
        begin
            initstorage
        rescue
            system("rm -rf %s" % Puppet[:checksumfile])
        end
    end

    def initstorage
        Puppet::Storage.init
        Puppet::Storage.load
    end

    def clearstorage
        Puppet::Storage.store
        Puppet::Storage.clear
    end

    def test_simplebucket
        name = "yayness"
        mkbucket(name, tempfile())

        bucket = nil
        assert_nothing_raised {
            bucket = Puppet.type(:filebucket).bucket(name)
        }

        assert_instance_of(Puppet::Client::Dipper, bucket)

        md5 = nil
        newpath = tempfile()
        @@tmpfiles << newpath
        system("cp /etc/passwd %s" % newpath)
        assert_nothing_raised {
            md5 = bucket.backup(newpath)
        }

        assert(md5)

        newmd5 = nil

        # Just in case the file isn't writable
        File.chmod(0644, newpath)
        File.open(newpath, "w") { |f| f.puts ";lkjasdf;lkjasdflkjwerlkj134lkj" }

        assert_nothing_raised {
            newmd5 = bucket.backup(newpath)
        }

        assert(md5 != newmd5)

        assert_nothing_raised {
            bucket.restore(newpath, md5)
        }

        File.open(newpath) { |f| newmd5 = Digest::MD5.hexdigest(f.read) }

        assert_equal(md5, newmd5)
    end

    def test_fileswithbuckets
        name = "yayness"
        mkbucket(name, tempfile())

        bucket = nil
        assert_nothing_raised {
            bucket = Puppet.type(:filebucket).bucket(name)
        }

        file = mktestfile()
        assert_nothing_raised {
            file[:backup] = ["filebucket", name]
        }

        opath = tempfile()
        @@tmpfiles << opath
        system("cp /etc/passwd %s" % opath)

        origmd5 = File.open(file.name) { |f| newmd5 = Digest::MD5.hexdigest(f.read) }

        file[:source] = opath
        #assert_nothing_raised {
        #    file[:backup] = true
        #}

        comp = newcomp("yaytest", file)

        trans = nil
        assert_nothing_raised {
            trans = comp.evaluate
        }
        events = nil
        assert_nothing_raised {
            events = trans.evaluate.collect { |e| e.event }
        }

        # so, we've now replaced the file with the opath file
        assert_equal(
            File.open(opath) { |f| newmd5 = Digest::MD5.hexdigest(f.read) },
            File.open(file.name) { |f| newmd5 = Digest::MD5.hexdigest(f.read) }
        )

        #File.chmod(0644, file.name)
        assert_nothing_raised {
            bucket.restore(file.name, origmd5)
        }

        assert_equal(
            origmd5,
            File.open(file.name) { |f| newmd5 = Digest::MD5.hexdigest(f.read) }
        )


    end
end
