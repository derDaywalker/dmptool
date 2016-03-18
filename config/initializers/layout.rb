# config/initializers/layout.rb
#
# Load the configuration options for the page header and page footer and
# initialize all missing definitions with their respective default values.

page_config = {
  header: {
    navigation: [
      {
        href: {controller: :static_pages, action: :home},
        label: {
          key: 'layouts.header.home_link',
          fallback: 'Home'
        }
      },
      {
        href: {controller: :dashboard, action: :show},
        if: :current_user,
        label: {
          key: 'layouts.header.dashboard_link',
          fallback: 'My Dashboard'
        }
      },
      {
        href: {controller: :static_pages, action: :guidance},
        label: {
          key: 'layouts.header.guidance_link',
          fallback: 'DMP Requirements'
        }
      },
      {
        href: {controller: :static_pages, action: :public},
        label: {
          key: 'layouts.header.public_dmps_link',
          fallback: 'Public DMPs'
        }
      },
      {
        href: 'http://blog.dmptool.org',
        label: {
          key: 'layouts.header.news_link',
          fallback: 'News'
        }
      },
      {
        href: {controller: :static_pages, action: :help},
        label: {
          key: 'layouts.header.help_link',
          fallback: 'Help'
        }
      },
      {
        href: {controller: :static_pages, action: :contact},
        label: {
          key: 'layouts.header.contact_link',
          fallback: 'Contact Us'
        }
      },
      {
        href: {controller: :static_pages, action: :about},
        label: {
          key: 'layouts.header.about_link',
          fallback: 'About'
        },
        children: [
          {
            href: 'http://dmptool.askbot.com',
            label: {
              key: 'layouts.header.faq_link',
              fallback: 'FAQ'
            }
          },
          {
            href: {controller: :static_pages, action: :video},
            label: {
              key: 'layouts.header.video_link',
              fallback: 'Video'
            }
          },
          {
            href: {controller: :static_pages, action: :partners},
            label: {
              key: 'layouts.header.parners_link',
              fallback: 'Partner Institutions'
            }
          }
        ]
      }
    ]
  },
  footer: {
    credits: lambda do
      "<p>DMPTOOL is a service of the <a href=\"http://www.cdlib.org/services/uc3\" title=\"University of California Curation Center\" target=\"_blank\">University of California Curation Center</a> of the <a href=\"http://cdlib.org\" title=\"California Digital Libary\" target=\"_blank\">California Digital Library</a><br/>Copyright &copy; 2010-#{Time.new.year} The Regents of the University of California</p>"
        .html_safe
    end,
    links: [
      {
        href: 'http://www.ucop.edu/electronic-accessibility/initiative/policy.html',
        label: {
          key: 'layouts.footer.accessibility_policy_link',
          fallback: 'Accessibility Policy'
        }
      },
      {
        href: {controller: :static_pages, action: :terms_of_use},
        label: {
          key: 'layouts.footer.terms_link',
          fallback: 'Terms of Use'
        }
      },
      {
        href: {controller: :static_pages, action: :contact},
        label: {
          key: 'layouts.footer.contact_link',
          fallback: 'Contact Us'
        }
      },
      {
        href: {controller: :static_pages, action: :about},
        label: {
          key: 'layouts.footer.about_link',
          fallback: 'About'
        },
        title: {
          key: 'layouts.footer.about_link_title',
          fallback: 'About the California Digital Library Data Management Tool'
        }
      },
    ],
    icons: [
      {
        type: :facebook,
        href: 'https://www.facebook.com/DMPTool',
        title: {
          key: 'layouts.footer.facebook_title',
          fallback: 'Follow the California Digital Library on Facebook'
        }
      },
      {
        type: :twitter,
        href: 'https://www.facebook.com/DMPTool',
        title: {
          key: 'layouts.footer.twitter_title',
          fallback: 'Follow the California Digital Library on Twitter'
        }
      },
      {
        type: :rss,
        href: 'https://www.facebook.com/DMPTool',
        title: {
          key: 'layouts.footer.rss_title',
          fallback: 'California Digital Library RSS Feed'
        }
      }
    ]
  }
}

filename = File.join(Rails.root, 'config', 'layout.rb')
if File.exists?(filename)
  page_config.deep_merge!(eval(IO.read(filename), binding, filename))
end

Layout.configure(page_config)
