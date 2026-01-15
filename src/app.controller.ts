import { Controller, Get, Post, UploadedFile, UseInterceptors } from '@nestjs/common';
import { AppService } from './app.service';
import { S3UploadInterceptor } from './s3-upload.interceptor';

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  getHello(): string {
    return this.appService.getHello();
  }

  @Post('upload')
  @UseInterceptors(S3UploadInterceptor)
  async uploadFile(@UploadedFile() file: Express.Multer.File & { location?: string; key?: string }) {
    return { file };
  }
}
