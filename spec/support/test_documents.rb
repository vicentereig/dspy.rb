# frozen_string_literal: true

require 'base64'

module TestDocuments
  module_function

  def create_base64_pdf(text: "Hello, World!")
    pdf = create_minimal_pdf(text: text)
    Base64.strict_encode64(pdf)
  end

  def create_minimal_pdf(text: "Hello, World!")
    content_stream = "BT /F1 12 Tf 100 700 Td (#{text}) Tj ET"

    objects = []
    objects << "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj"
    objects << "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj"
    objects << "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj"
    objects << "4 0 obj\n<< /Length #{content_stream.length} >>\nstream\n#{content_stream}\nendstream\nendobj"
    objects << "5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj"

    body = +"%PDF-1.4\n"
    offsets = []

    objects.each do |obj|
      offsets << body.length
      body << obj << "\n"
    end

    xref_offset = body.length
    xref = "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each do |offset|
      xref << format("%010d 00000 n \n", offset)
    end

    trailer = "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"

    body + xref + trailer
  end
end
