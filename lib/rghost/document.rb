##
#Ruby Ghost Engine - Document Builder.
#http://rghost.rubyforge.org
#Author Shairon Toledo <shairon.toledo at gmail.com> http://www.hashcode.eti.br
#Brazil Jun/2007
#
#Copyright (c) 2007-2008 Shairon Toledo
#
#Permission is hereby granted, free of charge, to any person
#obtaining a copy of this software and associated documentation
#files (the "Software"), to deal in the Software without
#restriction, including without limitation the rights to use,
#copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the
#Software is furnished to do so, subject to the following
#conditions:
#
#The above copyright notice and this permission notice shall be
#included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
#OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
#HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
#WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#FROM, OUT OF OR IN CONNECTION WITH

require 'ps_object'
require 'ps_facade'
require 'document_callback_facade'
require 'virtual_pages'
require 'variable'
require 'pdf_security'
#The Document class child of PsFacade is used to join postscript objects to generate output file. 

class RGhost::Document < RGhost::PsFacade 
  attr_reader :additional_params
  include RGhost::DocumentCallbackFacade
  include RGhost::RubyToPs
  DISABLE_VIRTUAL_PAGE=RGhost::Variable.new(:has_vp?, false)
  ENABLE_VIRTUAL_PAGE=RGhost::Variable.new(:has_vp?, true)
  DEFAULT_OPTIONS={
    :rows_per_page => 80 , 
    :count_pages => 10,
    :row_height => 0.4,
    :row_padding => 0.1,
    :font_encoding=> RGhost::Config::GS[:font_encoding],
    :paper => RGhost::Paper::DEFAULT_OPTIONS
  }
 
  #===Examples
  #Creating document with 80 rows per page and custom paper
  # doc=Document.new :rows_per_page => 80, paper => [30,5]
  #Document A4 with row height 0.5 and font encoding CodePage1252
  # doc=Document.new :row_height => 0.5, :font_encoding => 'CodePage1252'
  #Defining all margins
  # doc=Document.new :margin => 0.5
  # 
  # 
  #==Parameters
  #* <tt>:paper</tt> -  Facade to +paper+ defined on the construction of Paper class
  #* <tt>:margin, :duplex and :tuble</tt> - Facade to +options+ defined on the construction of Paper class
  #* <tt>:rows_per_page</tt> - Specifies count of rows per pages.
  #* <tt>:landscape</tt> - Whether true invert de size(width per height)
  #* <tt>:count_pages</tt> - Defines postscript internal variable to display with class TextIn. Example:
  #
  # doc=Document.new :count_pages => 10
  # doc.before_page_create :except => 1 do
  #  text_in :x => 15, :y => 5, :write => "Page %current_page% of %count_pages%"
  # end
  # 
  #The value above %count_pages% will be evaluated inside of document for all pages except page one.
  #* <tt>:fontsize</tt> - Defines the size of tag :default_font.
  #* <tt>:row_height and row_padding</tt> - Its names say by itself :)
  #* <tt>:font_encoding</tt> - Specifies encoding of data input. You can look for supported encoding using the method RGhost::Config.encode_test
  def initialize(options={})
    super()
    @head,@callbacks=RGhost::PsObject.new,RGhost::PsObject.new
    @head.set RGhost::Load.library(:type)
    @head.set RGhost::Load.library(:unit)
    
    @variables=DEFAULT_OPTIONS.dup.merge(options)
    default_encoding
    @paper=RGhost::Paper.new(options[:paper] || :A4, options)
    @head.set @paper
    @done=false
    @docinfo={:Producer => "Ruby Ghostscript - RGhost v#{RGhost::VERSION::STRING}" }
    @defines=[]
    @additional_params=[]
    
    default_variables
    
  end
  
  def gs_paper #:nodoc:
    @paper.gs_paper
  end
  #  

  #Creates map of tags if will be use in 'writable' classes(Show, Text, TextIn and TextArea). 
  #The font names file catalog can be generated by code below
  #  RGhost::Config.enviroment_fonts.render :pdf, :filename => "mycatalog.pdf"
  #this can take while. If waiting for much time you has any font with problem, remove some fonts mostly international fonts not used often.
  #Below little piece of catalog
  #link:images/font_catalog.png
  #
  #After genereted catalog you can map your tags. 
  #
  #
  #Tags has +name+ of tag(as Symbol) and its options. The options are
  #
  #* <tt>:name</tt> - Font name from catalog.
  #* <tt>:size</tt> - Font size.
  #* <tt>:color</tt> - Color.create facade
  #* <tt>:encoding</tt> - If true the font will be encoding using de pattern :font_encoding of the document.
  #* <tt>:from</tt> - Load True Type or Type1 font from file.
  #===Examples
  # d=Document.new :encoding => 'IsoLatin'
  # d.define_tags do
  #  tag :my_italic,    :name => 'Hershey-Gothic-Italian-Oblique', :size => 10
  #  tag :myfont,       :name => 'Hershey-Plain'
  #  tag :font_encoded, :name => 'NimbusMonL-Regu',    :size => 8,  :color => 0.5, :encoding => true
  #  tag :other_font,   :name => 'NimbusMonL-Regu',    :size => 10
  #  tag :arial,        :name => 'Arial-ItalicMT',     :color => '#ADAD66'
  #  tag :arial_bold,   :name => 'NimbusSanL-BoldItal',:size => 12, :color => '#ADAD66'
  #  tag :monaco,       :name => 'Monaco', :from => "/path/to/myfont.ttf", :size => 12
  # end
  #You can use :default_font tag for custom the default font.
  #===Using tags
  #====With Show class
  # doc.show 'My Text on this row', :with => :my_italic, :align => :page_center 
  #====With Show class overrinding tag's color.
  # doc.show 'My Text on this row', :with => :my_italic, :align => :page_center, :color => :red 
  #====With TextIn class.
  # doc.text_in :x=> 3, :y=> 10, :tag => :arial_bold , :write => "Here's point(3,10)"
  #====With Text
  # doc.text '<myfont>My Text</myfont>on this row.<arial>Other text</arial><my_italic>Italic font</my_italic>' 
  #====With TextArea
  # txt='<myfont>My Text</myfont>on this row.<arial>Other text</arial><my_italic>Italic font</my_italic>' 
  # doc.text_area txt, :text_align => :center, :width => 5, :x => 3, :y => 10
  #====Using tag
  # doc.use_tag :myfont
  # doc.show "Simple Text", :tag => nil # it will use :myfont
  # doc.show "Simple Text2", :tag => nil # it will use :myfont too
  def define_tags(&block)
    RGhost::Config::FONTMAP.instance_eval(&block)
  end   
    
  def ps #:nodoc:
    done unless @done
    
    
    
    out=RGhost::PsObject.new
    out.set @head
    out.raw formated_docinfo
    out.set @default_variables 
    out.set RGhost::Load.rg_enviroment
    out.raw @defines.join
    out.set RGhost::Cursor.moveto
    out.set RGhost::Config::FONTMAP
    out.set @callbacks
    out.set RGhost::Load.library(:begin_document)
    RGhost::Config::GS[:preload].uniq.each{|v| out.set RGhost::Load.library(v) }
    out.set RGhost::Cursor.moveto
    out.raw super
    out.raw "\n\n"
   
    "#{out} "
      
    #"#{@head} \n%%endhead\n#{@default_variables}\n\n #{Load.rg_enviroment} #{@defines.join} #{@callbacks} #{Load.library(:begin_document)}\n #{Cursor.moveto}#{super}"
    
    
  end
  #  def link(label,options={:to => 'http://rghost.rubyforge.net'})
  #    raw "/:link_str #{to_string(label)} def /:link_uri #{to_string(options[:to])} def :link_make"
  #    
  #  end
  #Facade to RubyGhostEngine.render
  #Converts a document to an output format, such as :pdf, :png, :ps, :jpeg, :tiff etc
  #The paramter device can be found at RGhost::Constants::Devices or at http://pages.cs.wisc.edu/~ghost/doc/cvs/Devices.htm
  #===Options
  #Method render have the following options available.
  #* <tt>:filename</tt> - File path.
  #* <tt>:logfile</tt> - Writes the converter's process into a file.
  #* <tt>:multipage</tt> - Whether true the output will be one page per file posfixed by _0001.ext, for example, for one file name 'test.png' with two pages will create test_001.png and test_002.png 
  #* <tt>:resolution</tt> - Integer value to output resolution.
  #* <tt>:quality</tt> - Presets the "distiller parameters" to one of four predefined settings:
  #       :screen   - selects low-resolution output similar to the Acrobat Distiller "Screen Optimized" setting.
  #       :ebook    - selects medium-resolution output similar to the Acrobat Distiller "eBook" setting.
  #       :printer  - selects output similar to the Acrobat Distiller "Print Optimized" setting.
  #       :prepress - selects output similar to Acrobat Distiller "Prepress Optimized" setting.
  #       :default  - selects output intended to be useful across a wide variety of uses, possibly at the expense of a larger output file.
  #* <tt>:size</tt> - Crops a single page using a string of dimension, example, '200x180', '140x90'.
  #* <tt>:range</tt> - Specifies range of pages(PDF only)
  #====Ghostscript interpreter options
  #   
  #Array of Hashes for Ghostscript interpreter look at http://pages.cs.wisc.edu/~ghost/doc/cvs/Use.htm#Parameter_switches for more details.
  #You can use two parameter :s and :d, examples
  #   :s => [{:GenericResourceDir => /dir, :DEFAULTPAPERSIZE=> "a3"}]
  #   :d => [ {:TextAlphaBits => 2}  ]
  #Or one string using the parameter :raw, as below
  #   :raw => "-sGenericResourceDir=/test -dTextAlphaBits=2"
  #
  #===Examples
  #  doc=Document.new
  #  #do something
  #  
  #  doc.render :pdf,  :filename => 'foo.pdf   # PDF output
  #  doc.render :pdf,  :filename => 'foo.pdf, :quality => :ebook   # PDF output
  #  doc.render :jpeg, :filename => 'foo.jpg'  # JPEG output
  #  doc.render :png,  :filename => 'foo.png',  :multipage => true      # PNG output one page per file
  #  doc.render :tiff, :filename => 'foo.tiff', :resolution => 300      # TIFF with 300dpi 
  #  doc.render :ps, :raw => '-sFONTMAP=/var/myoptional/font/map', :filename => 'test.ps'
  #
  #===Testing if has errors
  # doc=Document.new
  # doc.raw "hahahah!" #it produce error in ps stack
  # doc.render :jpeg, :filename => 'with_error.jpg'
  # puts r.errors  if r.error? #=> GPL Ghostscript 8.61: Unrecoverable error, exit code 1.\ Error: /undefined in hahahah!
  #      
  #===Printing
  #====Using printing system
  #  doc=Document.new
  #  #do something
  #  f="myjob.prn"  
  #  doc.render :laserjet, :filename => f
  #  `lpr #{f}`
  #====Windows shared printer
  # doc.render :eps9mid, :filename => "//machine/printer"
  def render(device,options={})
    rg=RGhost::Engine.new(self,options)
    rg.render(device)
    rg
  end
  #Behavior as render but returns content file after convertion.
  #===Example with Rails
  # def my_action
  #   doc=RGhost::Document.new
  #   #do something    
  #   send_data doc.render_stream(:pdf), :filename => "/tmp/myReport.pdf"   
  # end
  #
  #===TCP/IP direct printer
  # require 'socket'
  # 
  # doc=Document.new 
  # #do something    
  # printer = TCPSocket.open('192.168.1.70', 9100)  
  # printer.write doc.render_stream(:ps) 
  # printer.close
  def render_stream(device,options={})
    rg=render(device,options)
    out=rg.output.readlines.join
    rg.clear_output
    out
  end
  #Facade to Function.new
  #Defines low level function to optimize repetitive piece of code.
  #===Example
  # doc=Document.new
  # doc.define :piece do
  #   set Show.new("Hello")
  #   set Cursor.next_row
  #   set HorizontalLine.new(:middle)
  #   set Cursor.next_row
  # end
  # #Repeting ten times the same code
  # 10.times{ doc.call :piece }
  def define(name,&block)
    @defines << RGhost::Function.new("_#{name}",&block)
  end
  def define_variable(name,value)
    set RGhost::Variable.new(name,value)
  end
  #Defines a function using the method define after that call de function one time.
  def define_and_call(name,&block)
    define(name,&block)
    call(name)
  end
 
  #Prints the text file using the predefined tag +:pre+
  #===Example
  # doc=Document.new :paper => :A4, :landscape => true
  # doc.print_file "/etc/passwd"
  # doc.render :pdf, :filename => "/tmp/passwd.pdf
  def print_file(file)
    s=File.open(file).readlines.join.gsub(/</,'&lt').gsub(/>/,'&gt').gsub(/\n/,'<br/>')
    
    use_tag :pre
    set RGhost::Text.new(s,true)
    
  end
  #With method virtual_pages you can define any virtual pages per physical page. 
  #The cursor into virtual page jumps in column for each virtual page and run primitives next_page when ends columns. Look the example below.
  #Example for a document without virtual pages we will has
  # doc=Document.new
  # doc.text File.readlines("/tmp/mytext.txt")
  #will generate
  #
  #link:images/virtual_page1.png 
  #
  #Now for a document with 3 virtual pages
  # doc=Document.new
  # doc.virtual_pages do
  #   new_page :width => 4
  #   new_page :width => 7, :margin_left => 1
  #   new_page :width => 4, :margin_left => 1
  # end
  # doc.text File.readlines("/tmp/mytext.txt")
  #will generate
  #
  #link:images/virtual_page2.png 
  #
  #PS: The parameter margin left of first virtual page won't be used because it's will use page's margin left.
  def virtual_pages(&block)
    set RGhost::VirtualPages.new(&block)
  end
  {
       :base => -4,
     :print => -4,
     :modify => -8,
     :copy => -16,
     :annotate => -32,
     :interactive => -256,
     :copy_access =>  -512,
     :assemble => -1024,
     :high_quality_print => -2048,
     :all => -3904}
  
  #Security disable the permissions and define passwords to PDF documents. 
  #The password just support set of \w .
  #Always that use the block security should set owner and user password. By default the encryption is 3.
  #Document Security can be set with the permissions flags
  #===Disable options 
  #* <tt>:base or :print</tt> Print document (possibly not at the highest quality level).
  #* <tt>:modify</tt>Modify contents of document, except as controlled by :annotate, :interective and :assemble.
  #* <tt>:copy</tt>Copy text and graphics from document other than that controlled by :copy_access
  #* <tt>:annotate</tt>Add or modify text annotations, fill in interactive form fields, and if :interective is set, create or modify interactive form fields
  #* <tt>:interactive</tt>Fill in existing interacive form fields, even if :annotate is clear
  #* <tt>:copy_access</tt>Extract text and graphics (in support of accessibility to disabled users or for other purposes).
  #* <tt>:assemble</tt>Assemble the document (insert, rotate, or delete pages and create bookmarks or thumbnail images), even when :base is clear
  #* <tt>:high_quality_print</tt>Add or modify text annotations 
  #* <tt>:all</tt>Disable all permissions. 
  #===Example 1
  # doc.security do |sec|
  #   sec.owner_password ="owner" #password without space!
  #   sec.user_password ="user"   #password without space!
  #   sec.key_length = 128
  #   sec.disable :print, :copy, :high_quality
  # end
  #===Example 2
  #Disable all
  # doc.security do |sec|
  #   sec.owner_password ="owner" #password without space!
  #   sec.user_password ="user"   #password without space!
  #   sec.disable :all
  # end
  #
  def security
     sec=RGhost::PdfSecurity.new
     yield sec
     @additional_params << sec.gs_params
  end
  
  #Starts and Ends internal benckmark will write in bottom of page.
  #===Example
  # doc=Document.new
  # doc.benchmark :start
  # doc.... #do something
  # doc.benchmarck :stop
  # doc.render ...
  def benchmark(state=:start)
    case state
    when :stop
      moveto(:x => "20", :y => "20")
      raw %Q{
      default_font (RGhost::Ghostscript benchmark: ) show
      realtime benchmark sub 1000 div 20 string cvs show ( seconds ) show
      }
    when :start
      set RGhost::Variable.new(:benchmark,"realtime")
    end
  end
  
  #Rghost can make use of Encapsulated Postscript files to act as templates(EPS).
  #This way you can create the visual layout of the page using a graphics tool and just paint the dynamic pieces over using Rghost.
  #
  #link:images/templates_demo.jpg
  #
  #Above we have mytemplate.eps that was generated by a graphic app, my_ruby_program.rb that takes care of the positioning and at last the generated output.
  #
  #
  #A Template use example
  #Let's say that the files first.eps and content.eps already exist. Now we shall see how to create a document that uses the template first.eps for the cover and the rest of the document uses content.eps.
  #
  # d = Document.new :margin_top => 5, :margin_bottom => 2
  #
  #Just for the first page
  #
  # d.first_page do
  #  image "/my/dir/first.eps" 				#loads the template
  #  text_in :x=> 5, :y=> 17, :text => "My Report", :with => :big
  #  next_page 						#go to the next page using cursors
  # end
  #Callback for all other pages.
  #
  # d.before_page_create :except => 1 do
  #  image "/my/dir/content.eps"
  #  text_in :text => "Page %current_page% of %count_pages%", :x => 18, :y => 27, :with => :normal  
  # end
  # 
  #1500 rows 
  #
  # 1500.times do |n|
  #   d.show "Value #{n}"
  #   d.next_row
  # end
  #We have a cover page and 1500 rows, judging by the margins each page supports 46 rows, so we have 1500/46 = 32.60 pages plus the cover. Rounding it up totals 34 pages for the :count_pages
  #
  #  d.define_variable(:count_pages, 34) 
  #  d.showpage
  #  d.render :pdf, :filename => "/tmp/test.pdf"
  #  
  #If we knew the amount of pages beforehand we could state it on the creation of the document, i.e.
  #
  #  :current_pages => 34 
  #
  #The example uses  one template per page, but this is not a limit in RGhost. You can have multiple images and templates on per page. Just have to define the template:
  # 
  #   d=Document.new :margin_top => 5, :margin_bottom => 2
  #   d.define_template(:myform, '/local/template/form1.eps', :x=> 3, :y => 5)
  #   
  #and call it  on the document.
  #  d.use_template :myform
  #  
  #===Arguments
  #* <tt>:name</tt> - Template's name.
  #* <tt>:file_path</tt> - Path to file.
  #* <tt>:options</tt> - Options facade to Image.for(or image)
  def define_template(name,file_path,options={})
    
    @defines <<  RGhost::Function.new("_#{name}",RGhost::Image.for(file_path,options))
  end


  #Informs is ready to converts/prints
  def done
    @done=true
    raw "\n\n"
    call :after_page_create
    call :callback
    call :after_document_create
    
    showpage
    raw "\n%%EOF"
  end
  def enable_virtual_pages
    set RGhost::Variable.new(:has_vp?, true)
    
  end
  def disable_virtual_pages
    set RGhost::Variable.new(:has_vp?, false)
    set RGhost::Variable.new(:limit_left,  'source_limit_left')
    set RGhost::Variable.new(:limit_right, 'source_limit_right')
    
  end
   
  #Configures properties about your document.
  #The keys are supported :Creator, :Title, :Author, :Subject and :Keywords, or downcase as :title etc.
  #Example: 
  # doc.properties :Autor => "Shairon Toledo", :Title => "Learning RGhost" 
  def info(docinfo={})
    #puts docinfo.inspect
    @docinfo.merge!(docinfo)
    #puts @docinfo.inspect
  end
  
  #Creates Grid::Rails inside of the document. Facade to RGhost::Grid::Rails
  def rails_grid(default_columns_options={})
    
    grid=Grid::Rails.new(default_columns_options)
    yield grid
    grid.style(default_columns_options[:style]) if default_columns_options[:style]
    grid.data(default_columns_options[:data]) if default_columns_options[:data]
    set grid
    
  end
  #Creates Grid::CSV inside of the document. Facade to RGhost::Grid::CSV
  def csv_grid(default_columns_options={})
    grid=Grid::CSV.new(default_columns_options) 
    yield grid
    grid.style(default_columns_options[:style]) if default_columns_options[:style]
    grid.data(default_columns_options[:data]) if default_columns_options[:data]
    set grid
  end
  #Creates Grid::Matrix inside of the document. Facade to RGhost::Grid::Matrix
  def matrix_grid(default_columns_options={})
    grid=Grid::Matrix.new(default_columns_options) 
    yield grid
    grid.style(default_columns_options[:style]) if default_columns_options[:style]
    set grid
  end
  
  
  private
  
  def default_variables
    ps=RGhost::PsObject.new
    ps.set RGhost::Variable.new(:rows_per_page,@variables[:rows_per_page])
    ps.set RGhost::Variable.new(:count_pages,@variables[:count_pages])
    ps.set RGhost::Variable.new(:row_height,RGhost::Units::parse(@variables[:row_height]))
    ps.set RGhost::Variable.new(:row_padding,RGhost::Units::parse(@variables[:row_padding]))
    
    @default_variables=ps  
    
  end
  
  def default_encoding
    @head.set RGhost::Load.library(@variables[:font_encoding],:enc)
    @head.set RGhost::Variable.new(:default_encoding,@variables[:font_encoding])
    
  end
  def formated_docinfo
    d=["["]
    
    @docinfo.each do |k,v|
      d << "/#{k.to_s.capitalize}"
      d << to_string(v)
    end
    d << "/DOCINFO"
    d << "pdfmark "
    d.join(" ")
  end
  
end


